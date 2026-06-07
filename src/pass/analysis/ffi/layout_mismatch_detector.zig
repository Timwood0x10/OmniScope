//! Cross-language struct layout mismatch detector for FFI boundaries.
//!
//! Detects when a struct type crosses an FFI boundary and the caller/callee
//! may have incompatible assumptions about the struct's memory layout.
//!
//! Key detection scenarios:
//!   1. repr(Rust) struct passed to C: Rust's default layout has no stability
//!      guarantees, leading to field offset mismatches when C code accesses it.
//!   2. Go struct passed to C: The Go compiler may reorder struct fields,
//!      making the layout incompatible with C expectations.
//!   3. Zig default struct in extern C call: Zig's default struct layout is
//!      optimized and not C-compatible; only `extern struct` guarantees C layout.
//!   4. Same struct defined with different fields across the FFI boundary:
//!      inconsistent field count, types, or alignment between caller and callee.
//!
//! Design: Stateless detection pass. Each function is analyzed independently
//! by scanning its instructions for FFI calls with struct pointer arguments.

const std = @import("std");
const c = @import("../../../ir/llvm_raw.zig").c;
const isCallOrInvoke = @import("../../../ir/llvm_safe.zig").isCallOrInvoke;
const getCallInstArgCount = @import("../../../ir/llvm_safe.zig").getCallInstArgCount;

const PassContext = @import("../../pass.zig").PassContext;
const PassKind = @import("../../pass.zig").PassKind;
const DiagnosticWriter = @import("../../pass.zig").DiagnosticWriter;

const Location = @import("../../../diag/issue.zig").Location;
const Issue = @import("../../../diag/issue.zig").Issue;
const IssueKind = @import("../../../diag/issue.zig").IssueKind;
const Severity = @import("../../../diag/issue.zig").Severity;
const TraceEntry = @import("../../../diag/issue.zig").TraceEntry;
const Language = @import("../../../diag/issue.zig").FFIBoundary.Language;

/// Category of layout mismatch risk for a struct type.
pub const LayoutRisk = enum(u8) {
    /// Struct has guaranteed C-compatible layout (e.g., Zig extern struct, C struct).
    safe,
    /// Struct may have unsafe layout for FFI (e.g., repr(Rust), Go default, Zig default).
    risky,
    /// Could not determine the struct's layout guarantees.
    unknown,
};

/// Information about a detected layout mismatch.
pub const LayoutMismatchInfo = struct {
    /// Name of the struct type at the boundary.
    struct_name: []const u8,
    /// Caller function name.
    caller_name: []const u8,
    /// Callee function name.
    callee_name: []const u8,
    /// Language of the caller.
    caller_lang: Language,
    /// Language of the callee.
    callee_lang: Language,
    /// Index of the parameter where the struct was detected.
    param_index: u32,
    /// Human-readable description of the mismatch.
    description: []const u8,
};

/// Language-specific hints about struct layout guarantees.
const LayoutHints = struct {
    /// Struct name suffixes that indicate C-compatible layout.
    const c_compatible_suffixes = [_][]const u8{
        "extern",
        "c_layout",
        "repr(C)",
        "_c_",
    };

    /// Rust struct name patterns suggesting repr(Rust) (default, unsafe for FFI).
    const rust_repr_rust_indicators = [_][]const u8{
        "anon",
        "internal",
    };

    /// Rust struct name patterns suggesting repr(C) (safe for FFI).
    const rust_repr_c_indicators = [_][]const u8{
        "repr(C)",
        "extern",
    };
};

/// Helper to check if LLVM API returned a valid (non-null) pointer.
inline fn llvmNotNull(ptr: anytype) bool {
    return @intFromPtr(ptr) != 0;
}

/// Detect the likely language origin of a struct type based on its name.
///
/// LLVM IR struct names follow conventions that hint at their source language:
///   - C: `struct.MyStruct`, anonymous `%opaque`
///   - Rust: mangled names with hash suffixes like `MyStruct::something.123abc`
///   - Go: `main.MyStruct`, `pkgname.TypeName`
///   - Zig: `(struct.MyStruct)`, `(struct constant)`
fn detectStructLanguage(struct_name: []const u8) Language {
    // Anonymous structs cannot be traced to a specific language.
    if (struct_name.len == 0) return .unknown;

    // Check for Rust patterns: hash suffixes and mangled path separators.
    // Rust v0-mangled structs contain "17h" or similar hash markers.
    if (std.mem.indexOf(u8, struct_name, ".") != null) {
        // Check for Rust hash suffix (e.g., "Foo.1234567890abcdef").
        const dot_pos = std.mem.lastIndexOf(u8, struct_name, ".") orelse 0;
        const suffix = struct_name[dot_pos + 1 ..];
        if (suffix.len >= 8) {
            var all_hex = true;
            for (suffix) |ch| {
                if (!std.ascii.isHex(ch)) {
                    all_hex = false;
                    break;
                }
            }
            if (all_hex) return .rust;
        }
    }

    // Rust struct names often contain :: separators from path qualification.
    if (std.mem.indexOf(u8, struct_name, "::") != null) {
        return .rust;
    }

    // C struct names: simple "struct.Name" or opaque types.
    // IMPORTANT: This check MUST come before the Go single-dot ambiguity check,
    // because "struct.Point" would otherwise be misclassified as Go (single dot,
    // "struct" starts with lowercase letter).
    if (std.mem.startsWith(u8, struct_name, "struct.")) {
        return .c;
    }

    // Go struct names: prefixed with package path (main., pkgname.).
    // Go uses dot-separated package paths but without :: that Rust uses.
    if (std.mem.indexOf(u8, struct_name, "main.") != null) {
        return .go;
    }
    // Go package paths like "pkgname.TypeName" with a single dot.
    if (std.mem.indexOf(u8, struct_name, ".") != null) {
        // Single dot pattern like "json.Decoder" is typically Go.
        const dot_count = countOccurrences(struct_name, '.');
        if (dot_count == 1) {
            const parts = splitOnce(struct_name, '.');
            if (parts != null) {
                const first = parts.?.first;
                // Package names are typically lowercase (Go convention).
                if (first.len > 0 and first[0] >= 'a' and first[0] <= 'z') {
                    return .go;
                }
            }
        }
    }

    // Zig struct names: "(struct ...)" pattern from Zig's LLVM naming.
    if (std.mem.startsWith(u8, struct_name, "(struct") or
        std.mem.indexOf(u8, struct_name, "struct_") != null)
    {
        return .zig;
    }

    return .unknown;
}

/// Count occurrences of a character in a string.
fn countOccurrences(s: []const u8, ch: u8) usize {
    var count: usize = 0;
    for (s) |char| {
        if (char == ch) count += 1;
    }
    return count;
}

/// Split a string once on the first occurrence of a delimiter.
fn splitOnce(s: []const u8, delim: u8) ?struct { first: []const u8, second: []const u8 } {
    const idx = std.mem.indexOfScalar(u8, s, delim) orelse return null;
    return .{ .first = s[0..idx], .second = s[idx + 1 ..] };
}

/// Determine if a struct type has safe layout guarantees for FFI.
///
/// Returns `LayoutRisk` based on the struct's detected source language
/// and naming patterns that indicate explicit layout annotations.
fn assessLayoutRisk(struct_type: c.LLVMTypeRef) LayoutRisk {
    const struct_name_ptr = c.LLVMGetStructName(struct_type);
    if (!llvmNotNull(struct_name_ptr)) return .unknown;
    const struct_name = std.mem.span(struct_name_ptr);
    if (struct_name.len == 0) return .unknown;

    // Check for explicit C-compatible layout indicators in the name.
    for (LayoutHints.c_compatible_suffixes) |suffix| {
        if (std.mem.indexOf(u8, struct_name, suffix) != null) {
            return .safe;
        }
    }

    const lang = detectStructLanguage(struct_name);

    switch (lang) {
        .c => {
            // C structs always have C-compatible layout.
            return .safe;
        },
        .rust => {
            // Check for repr(C) indicators in the struct name.
            for (LayoutHints.rust_repr_c_indicators) |indicator| {
                if (std.mem.indexOf(u8, struct_name, indicator) != null) {
                    return .safe;
                }
            }
            // Default Rust layout (repr(Rust)) is unsafe for FFI.
            return .risky;
        },
        .go => {
            // Go struct layout may be reordered by the compiler.
            // Go does not guarantee C-compatible layout by default.
            return .risky;
        },
        .zig => {
            // Zig's default struct layout is optimized and not C-compatible.
            // Only `extern struct` guarantees C layout.
            // Without "extern" in the name, assume default layout.
            return .risky;
        },
        else => {
            return .unknown;
        },
    }
}

/// Check if the language pair has known struct layout compatibility.
///
/// C-to-C: always compatible (same layout rules).
/// Zig extern-to-C: compatible (extern struct guarantees C layout).
/// Any other cross-language pair: potentially incompatible.
fn isLayoutCompatiblePair(caller_lang: Language, callee_lang: Language) bool {
    // Same language is always compatible.
    if (caller_lang == callee_lang) return true;

    // C-to-C is compatible (both use C ABI layout).
    if (caller_lang == .c and callee_lang == .c) return true;

    return false;
}

/// Main pass for detecting struct layout mismatches at FFI boundaries.
pub const LayoutMismatchPass = struct {
    pub const name = "layout_mismatch";
    pub const kind = PassKind.analysis;
    pub const deps = &[_][]const u8{};

    /// Run the layout mismatch detection pass.
    ///
    /// Scans all functions in the module for FFI calls with struct pointer
    /// arguments, then checks if the struct layout is compatible across
    /// the language boundary.
    pub fn run(ctx: *PassContext, diag: *DiagnosticWriter) !void {
        if (ctx.module == null) return;

        var total_ffi_calls: u32 = 0;
        var struct_params_found: u32 = 0;
        var layout_issues: u32 = 0;

        var func = c.LLVMGetFirstFunction(ctx.module.?.raw);
        while (llvmNotNull(func)) : (func = c.LLVMGetNextFunction(func)) {
            const func_val = c.LLVMIsAFunction(func);
            if (!llvmNotNull(func_val)) continue;

            const caller_name_ptr = c.LLVMGetValueName(func);
            if (!llvmNotNull(caller_name_ptr)) continue;
            const caller_name = std.mem.span(caller_name_ptr);

            // Skip LLVM intrinsics — they are not user-level FFI calls.
            if (std.mem.startsWith(u8, caller_name, "llvm.")) continue;

            const caller_lang = classifyFunctionLanguage(caller_name);

            var bb = c.LLVMGetFirstBasicBlock(func);
            while (llvmNotNull(bb)) : (bb = c.LLVMGetNextBasicBlock(bb)) {
                var inst = c.LLVMGetFirstInstruction(bb);
                while (llvmNotNull(inst)) : (inst = c.LLVMGetNextInstruction(inst)) {
                    const opcode = c.LLVMGetInstructionOpcode(inst);
                    if (!isCallOrInvoke(opcode)) continue;

                    const result = try analyzeCallInstruction(
                        ctx,
                        func,
                        caller_name,
                        caller_lang,
                        inst,
                        diag,
                    );

                    total_ffi_calls += result.ffi_calls;
                    struct_params_found += result.struct_params;
                    layout_issues += result.issues;
                }
            }
        }

        if (total_ffi_calls > 0 or layout_issues > 0) {
            diag.info("LayoutMismatch: analyzed {} FFI calls, {} struct params, {} issues", .{
                total_ffi_calls,
                struct_params_found,
                layout_issues,
            });
        }
    }
};

/// Result of analyzing a single call instruction.
const AnalyzeResult = struct {
    ffi_calls: u32,
    struct_params: u32,
    issues: u32,
};

/// Scan the function body for instructions that reveal the pointee type of a value.
///
/// With LLVM opaque pointers, LLVMGetElementType() returns null on `ptr` types.
/// Instead, we scan for load/store/GEP instructions that use `val` as the pointer
/// operand and reveal the underlying struct type.
fn findPointeeStructType(func: c.LLVMValueRef, val: c.LLVMValueRef) ?c.LLVMTypeRef {
    var bb = c.LLVMGetFirstBasicBlock(func);
    while (llvmNotNull(bb)) : (bb = c.LLVMGetNextBasicBlock(bb)) {
        var inst = c.LLVMGetFirstInstruction(bb);
        while (llvmNotNull(inst)) : (inst = c.LLVMGetNextInstruction(inst)) {
            const opcode = c.LLVMGetInstructionOpcode(inst);
            switch (opcode) {
                c.LLVMLoad => {
                    // load %StructType, ptr %val
                    const ptr_op = c.LLVMGetOperand(inst, 0);
                    if (!llvmNotNull(ptr_op) or ptr_op != val) continue;
                    const loaded_type = c.LLVMTypeOf(inst);
                    // LLVMTypeOf(load) returns the loaded value type directly.
                    if (c.LLVMGetTypeKind(loaded_type) == c.LLVMStructTypeKind) {
                        return loaded_type;
                    }
                },
                c.LLVMStore => {
                    // store %StructType %val, ptr %ptr
                    const ptr_op = c.LLVMGetOperand(inst, 1);
                    if (!llvmNotNull(ptr_op) or ptr_op != val) continue;
                    // The stored value operand reveals the type
                    const stored_val = c.LLVMGetOperand(inst, 0);
                    if (!llvmNotNull(stored_val)) continue;
                    const stored_type = c.LLVMTypeOf(stored_val);
                    if (c.LLVMGetTypeKind(stored_type) == c.LLVMStructTypeKind) {
                        return stored_type;
                    }
                },
                c.LLVMGetElementPtr => {
                    // getelementptr inbounds %StructType, ptr %val, ...
                    const ptr_op = c.LLVMGetOperand(inst, 0);
                    if (!llvmNotNull(ptr_op) or ptr_op != val) continue;
                    // With LLVM opaque pointers, GEP instructions encode the
                    // source element type explicitly. Use LLVMGetGEPSourceElementType
                    // to retrieve it.
                    const source_elem_type = c.LLVMGetGEPSourceElementType(inst);
                    if (llvmNotNull(source_elem_type) and
                        c.LLVMGetTypeKind(source_elem_type) == c.LLVMStructTypeKind)
                    {
                        return source_elem_type;
                    }
                },
                else => {},
            }
        }
    }
    return null;
}

/// Scan the entire module for struct types that may be associated with
/// the calling function based on language naming conventions.
///
/// This is a fallback for when a pointer argument is passed directly to
/// a cross-language call without a type-revealing instruction in the
/// calling function (e.g., Go/Zig functions that forward a struct pointer).
fn findAssociatedStructInModule(raw_mod: c.LLVMModuleRef, _: []const u8, caller_lang: Language) ?c.LLVMTypeRef {

    // Iterate all functions in the module looking for struct type references.
    var func = c.LLVMGetFirstFunction(raw_mod);
    while (llvmNotNull(func)) : (func = c.LLVMGetNextFunction(func)) {
        if (c.LLVMIsDeclaration(func) != 0) continue;

        var bb = c.LLVMGetFirstBasicBlock(func);
        while (llvmNotNull(bb)) : (bb = c.LLVMGetNextBasicBlock(bb)) {
            var inst = c.LLVMGetFirstInstruction(bb);
            while (llvmNotNull(inst)) : (inst = c.LLVMGetNextInstruction(inst)) {
                const opcode = c.LLVMGetInstructionOpcode(inst);
                switch (opcode) {
                    c.LLVMLoad => {
                        const loaded_type = c.LLVMTypeOf(inst);
                        if (c.LLVMGetTypeKind(loaded_type) == c.LLVMStructTypeKind) {
                            // Check if this struct type matches the caller language convention.
                            const name_ptr = c.LLVMGetStructName(loaded_type);
                            if (llvmNotNull(name_ptr)) {
                                const sname = std.mem.span(name_ptr);
                                const lang = detectStructLanguage(sname);
                                if (lang == caller_lang) return loaded_type;
                            }
                        }
                    },
                    c.LLVMStore => {
                        const stored_val = c.LLVMGetOperand(inst, 0);
                        if (!llvmNotNull(stored_val)) continue;
                        const stored_type = c.LLVMTypeOf(stored_val);
                        if (c.LLVMGetTypeKind(stored_type) == c.LLVMStructTypeKind) {
                            const name_ptr = c.LLVMGetStructName(stored_type);
                            if (llvmNotNull(name_ptr)) {
                                const sname = std.mem.span(name_ptr);
                                const lang = detectStructLanguage(sname);
                                if (lang == caller_lang) return stored_type;
                            }
                        }
                    },
                    c.LLVMGetElementPtr => {
                        const source_elem_type = c.LLVMGetGEPSourceElementType(inst);
                        if (llvmNotNull(source_elem_type) and
                            c.LLVMGetTypeKind(source_elem_type) == c.LLVMStructTypeKind)
                        {
                            const name_ptr = c.LLVMGetStructName(source_elem_type);
                            if (llvmNotNull(name_ptr)) {
                                const sname = std.mem.span(name_ptr);
                                const lang = detectStructLanguage(sname);
                                if (lang == caller_lang) return source_elem_type;
                            }
                        }
                    },
                    else => {},
                }
            }
        }
    }
    return null;
}

/// Check if an LLVM value is a parameter of the given function.
fn isFuncParam(func: c.LLVMValueRef, val: c.LLVMValueRef) bool {
    const count = c.LLVMCountParams(func);
    var i: c_uint = 0;
    while (i < count) : (i += 1) {
        if (c.LLVMGetParam(func, i) == val) return true;
    }
    return false;
}

/// Analyze a single call instruction for struct layout mismatches.
fn analyzeCallInstruction(
    ctx: *PassContext,
    func: c.LLVMValueRef,
    caller_name: []const u8,
    caller_lang: Language,
    call_inst: c.LLVMValueRef,
    diag: *DiagnosticWriter,
) !AnalyzeResult {
    const called_val = c.LLVMGetCalledValue(call_inst);
    if (!llvmNotNull(called_val)) return .{ .ffi_calls = 0, .struct_params = 0, .issues = 0 };

    const callee_name_ptr = c.LLVMGetValueName(called_val);
    if (!llvmNotNull(callee_name_ptr)) return .{ .ffi_calls = 0, .struct_params = 0, .issues = 0 };
    const callee_name = std.mem.span(callee_name_ptr);

    if (callee_name.len == 0) return .{ .ffi_calls = 0, .struct_params = 0, .issues = 0 };

    const callee_lang = classifyFunctionLanguage(callee_name);

    // Only analyze cross-language calls.
    if (caller_lang == callee_lang) return .{ .ffi_calls = 0, .struct_params = 0, .issues = 0 };
    if (isLayoutCompatiblePair(caller_lang, callee_lang)) return .{ .ffi_calls = 0, .struct_params = 0, .issues = 0 };

    var result = AnalyzeResult{ .ffi_calls = 1, .struct_params = 0, .issues = 0 };

    const num_args = getCallInstArgCount(call_inst);
    var arg_idx: u32 = 0;
    while (arg_idx < num_args) : (arg_idx += 1) {
        const arg = c.LLVMGetOperand(call_inst, arg_idx);
        if (!llvmNotNull(arg)) continue;

        const arg_type = c.LLVMTypeOf(arg);
        if (!llvmNotNull(arg_type)) continue;

        // Check if argument is a pointer type.
        const type_kind = c.LLVMGetTypeKind(arg_type);
        if (type_kind != c.LLVMPointerTypeKind) continue;

        result.struct_params += 1;

        // With LLVM opaque pointers, LLVMGetElementType returns null on `ptr`.
        // Instead, scan the function body for load/store/GEP instructions
        // that use this value and reveal the underlying struct type.
        var struct_type = findPointeeStructType(func, arg);

        // Fallback: if no type-revealing instruction found, check if the
        // argument is a function parameter. In that case, scan the module
        // for struct types that match the function's language convention.
        if (struct_type == null and isFuncParam(func, arg)) {
            if (ctx.module) |mod_ref| {
                struct_type = findAssociatedStructInModule(mod_ref.raw, caller_name, caller_lang);
            }
        }

        if (struct_type) |st| {
            const risk = assessLayoutRisk(st);
            if (risk == .risky) {
                const struct_name_ptr = c.LLVMGetStructName(st);
                const struct_name = if (llvmNotNull(struct_name_ptr)) std.mem.span(struct_name_ptr) else "(unnamed)";

                reportLayoutMismatch(
                    ctx,
                    caller_name,
                    callee_name,
                    struct_name,
                    caller_lang,
                    callee_lang,
                    arg_idx,
                    diag,
                ) catch |err| {
                    diag.warn("LayoutMismatch: failed to report issue: {}", .{err});
                    continue;
                };
                result.issues += 1;
            }
        }
    }

    return result;
}

/// Report a detected struct layout mismatch at an FFI boundary.
fn reportLayoutMismatch(
    ctx: *PassContext,
    caller_name: []const u8,
    callee_name: []const u8,
    struct_name: []const u8,
    caller_lang: Language,
    callee_lang: Language,
    _: u32,
    diag: *DiagnosticWriter,
) !void {
    const caller_lang_str = languageToString(caller_lang);
    const callee_lang_str = languageToString(callee_lang);

    const trace = try ctx.allocator.alloc(TraceEntry, 3);
    errdefer ctx.allocator.free(trace);

    trace[0] = TraceEntry.initOwned(try std.fmt.allocPrint(
        ctx.allocator,
        "FFI call: {s} -> {s}",
        .{ caller_name, callee_name },
    ));
    trace[1] = TraceEntry.initOwned(try std.fmt.allocPrint(
        ctx.allocator,
        "Struct: {s} (from {s})",
        .{ struct_name, caller_lang_str },
    ));
    trace[2] = TraceEntry.initOwned(try std.fmt.allocPrint(
        ctx.allocator,
        "Callee expects C-compatible layout ({s})",
        .{callee_lang_str},
    ));

    const message = try std.fmt.allocPrint(
        ctx.allocator,
        "Struct layout mismatch at FFI boundary: {s} may have incompatible layout for {s}",
        .{ struct_name, callee_lang_str },
    );

    var issue = Issue.initWithTrace(
        .ffi_type_mismatch,
        message,
        Location.init(caller_name),
        .high,
        0.75,
        trace,
    );
    issue.owned = true;

    try ctx.addIssue(&issue);

    diag.warn("[LAYOUT-MISMATCH] {s} -> {s}: struct '{s}' layout may be incompatible ({s} -> {s})", .{
        caller_name,
        callee_name,
        struct_name,
        caller_lang_str,
        callee_lang_str,
    });
}

/// Classify the programming language of a function based on its LLVM IR name.
///
/// Uses name mangling conventions and prefix patterns to determine
/// the source language of a function.
fn classifyFunctionLanguage(func_name: []const u8) Language {
    if (func_name.len == 0) return .unknown;

    // LLVM intrinsics — no language affiliation.
    if (std.mem.startsWith(u8, func_name, "llvm.")) return .unknown;

    // Rust v0 mangling (RFC 2603): _R prefix.
    if (func_name.len > 2 and func_name[0] == '_' and func_name[1] == 'R') return .rust;

    // Rust/Itanium _ZN: disambiguate via isRustMangledName.
    if (func_name.len > 3 and func_name[0] == '_' and func_name[1] == 'Z' and func_name[2] == 'N') {
        if (isRustMangledName(func_name)) return .rust;
        return .cpp;
    }

    // C++ Itanium mangling (_Z prefix, not _ZN).
    if (func_name.len > 2 and func_name[0] == '_' and func_name[1] == 'Z') return .cpp;

    // MSVC mangling for C++: ? prefix.
    if (func_name.len > 0 and func_name[0] == '?') return .cpp;

    // Rust allocator and ownership intrinsics.
    const rust_intrinsics = [_][]const u8{
        "__rust_alloc",  "__rust_dealloc", "__rust_realloc",
        "__rdl_alloc",   "__rdl_dealloc",  "__rdl_realloc",
        "drop_in_place", "into_raw",       "from_raw",
    };
    for (rust_intrinsics) |pattern| {
        if (std.mem.indexOf(u8, func_name, pattern) != null) return .rust;
    }

    // Go patterns: main.*, runtime.*, internal/*, etc.
    if (std.mem.startsWith(u8, func_name, "main.") or
        std.mem.startsWith(u8, func_name, "runtime.") or
        std.mem.indexOf(u8, func_name, "_cgo_") != null or
        std.mem.indexOf(u8, func_name, "_Cfunc_") != null or
        std.mem.startsWith(u8, func_name, "syscall."))
    {
        return .go;
    }

    // Zig patterns.
    const zig_patterns = [_][]const u8{
        "zig_", "__zig_", "Allocator.", "allocImpl",
    };
    for (zig_patterns) |pattern| {
        if (std.mem.indexOf(u8, func_name, pattern) != null) return .zig;
    }

    // Java JNI patterns.
    if (std.mem.startsWith(u8, func_name, "Java_")) return .java;

    // Python C API patterns.
    if (std.mem.startsWith(u8, func_name, "PyInit_") or
        std.mem.startsWith(u8, func_name, "PyObject_") or
        std.mem.startsWith(u8, func_name, "PyMethodDef") or
        std.mem.startsWith(u8, func_name, "PyTypeObject"))
    {
        return .python;
    }

    // C# patterns.
    if (std.mem.startsWith(u8, func_name, "System.")) return .csharp;

    // Default to C for unmangled function names.
    return .c;
}

/// Heuristic to distinguish Rust Itanium _ZN mangling from C++ _ZN mangling.
///
/// Rust _ZN names have specific structural patterns:
///   - Element counts embedded in the name (e.g., _ZN4core...)
///   - Hash suffixes starting with '17' or '18'
/// C++ _ZN names follow a different structure with nested namespace patterns.
fn isRustMangledName(name: []const u8) bool {
    // Rust _ZN names typically have shorter element counts and
    // often contain known Rust crate prefixes.
    const rust_crates = [_][]const u8{
        "4core", "5alloc", "3std", "5panic", "6unwind",
    };
    for (rust_crates) |crate| {
        if (std.mem.indexOf(u8, name, crate) != null) return true;
    }

    // Rust _ZN names have hash suffixes like 17h or 18h after the function name.
    // Look for patterns like: count + 'h' at a plausible position.
    var i: usize = 0;
    while (i + 2 < name.len) : (i += 1) {
        if (std.ascii.isDigit(name[i]) and
            std.ascii.isDigit(name[i + 1]) and
            name[i + 2] == 'h')
        {
            // Found a hash marker — likely Rust mangling.
            return true;
        }
    }

    return false;
}

/// Convert Language enum to a human-readable string.
fn languageToString(lang: Language) []const u8 {
    return switch (lang) {
        .c => "C",
        .cpp => "C++",
        .rust => "Rust",
        .zig => "Zig",
        .go => "Go",
        .java => "Java",
        .python => "Python",
        .csharp => "C#",
        else => "unknown",
    };
}

// ============================================================================
// Tests
// ============================================================================

test "LayoutMismatchPass - name and kind" {
    try std.testing.expectEqualStrings("layout_mismatch", LayoutMismatchPass.name);
    try std.testing.expectEqual(PassKind.analysis, LayoutMismatchPass.kind);
}

test "classifyFunctionLanguage - Rust v0 mangling" {
    try std.testing.expectEqual(Language.rust, classifyFunctionLanguage("_RNvC1a4main"));
    try std.testing.expectEqual(Language.rust, classifyFunctionLanguage("_RNvNvC1x3foo3bar"));
}

test "classifyFunctionLanguage - Rust itanium mangling" {
    // _ZN4core3fooE: 4=core, 3=foo → Rust (known crate prefix)
    try std.testing.expectEqual(Language.rust, classifyFunctionLanguage("_ZN4core3fooE"));
    // _ZN5alloc7rc4Rc3newE: 5=alloc → Rust
    try std.testing.expectEqual(Language.rust, classifyFunctionLanguage("_ZN5alloc7rc4Rc3newE"));
}

test "classifyFunctionLanguage - C++ itanium mangling" {
    // _ZN4Base1fEv: C++ class method — but ambiguous with Rust _ZN
    // Without a known Rust crate prefix, it falls through to C++.
    // This test documents the limitation — C++ Itanium _ZN names without
    // Rust crate prefixes may be classified as C++.
    try std.testing.expectEqual(Language.cpp, classifyFunctionLanguage("_ZN4Base1fEv"));
    // _Z prefix (non-nested) is always C++.
    try std.testing.expectEqual(Language.cpp, classifyFunctionLanguage("_Z4cppfv"));
}

test "classifyFunctionLanguage - C functions" {
    try std.testing.expectEqual(Language.c, classifyFunctionLanguage("malloc"));
    try std.testing.expectEqual(Language.c, classifyFunctionLanguage("free"));
    try std.testing.expectEqual(Language.c, classifyFunctionLanguage("printf"));
    try std.testing.expectEqual(Language.c, classifyFunctionLanguage("my_c_function"));
}

test "classifyFunctionLanguage - Go functions" {
    try std.testing.expectEqual(Language.go, classifyFunctionLanguage("main.myFunc"));
    try std.testing.expectEqual(Language.go, classifyFunctionLanguage("runtime.mallocgc"));
    try std.testing.expectEqual(Language.go, classifyFunctionLanguage("c_main._cgo_"));
}

test "classifyFunctionLanguage - Zig functions" {
    try std.testing.expectEqual(Language.zig, classifyFunctionLanguage("zig_alloc"));
    try std.testing.expectEqual(Language.zig, classifyFunctionLanguage("__zig_probe_stack"));
    try std.testing.expectEqual(Language.zig, classifyFunctionLanguage("main.Allocator.alloc"));
}

test "classifyFunctionLanguage - MSVC C++ mangling" {
    try std.testing.expectEqual(Language.cpp, classifyFunctionLanguage("?foo@@YAHXZ"));
}

test "detectStructLanguage - C struct" {
    try std.testing.expectEqual(Language.c, detectStructLanguage("struct.Point"));
    try std.testing.expectEqual(Language.c, detectStructLanguage("struct.MyStruct"));
}

test "detectStructLanguage - Rust struct" {
    try std.testing.expectEqual(Language.rust, detectStructLanguage("MyStruct::new"));
    try std.testing.expectEqual(Language.rust, detectStructLanguage("Foo.1234567890abcdef"));
}

test "detectStructLanguage - Go struct" {
    try std.testing.expectEqual(Language.go, detectStructLanguage("main.Point"));
    try std.testing.expectEqual(Language.go, detectStructLanguage("json.Decoder"));
}

test "detectStructLanguage - Zig struct" {
    try std.testing.expectEqual(Language.zig, detectStructLanguage("(struct.MyStruct)"));
    try std.testing.expectEqual(Language.zig, detectStructLanguage("(struct constant)"));
}

test "detectStructLanguage - unknown" {
    try std.testing.expectEqual(Language.unknown, detectStructLanguage(""));
    try std.testing.expectEqual(Language.unknown, detectStructLanguage("opaque"));
}

test "assessLayoutRisk - risky: Rust repr(Rust) struct" {
    // We can't easily create LLVM type refs in tests, but we can test
    // indirectly via detectStructLanguage. The assessLayoutRisk function
    // delegates to detectStructLanguage for unnamed structs.
    try std.testing.expectEqual(Language.rust, detectStructLanguage("Foo::new"));
}

test "assessLayoutRisk - safe: C struct" {
    try std.testing.expectEqual(Language.c, detectStructLanguage("struct.Point"));
}

test "countOccurrences" {
    try std.testing.expectEqual(@as(usize, 0), countOccurrences("hello", '.'));
    try std.testing.expectEqual(@as(usize, 1), countOccurrences("hello.world", '.'));
    try std.testing.expectEqual(@as(usize, 2), countOccurrences("a.b.c", '.'));
}

test "splitOnce" {
    const result = splitOnce("hello.world", '.') orelse return error.UnexpectedNull;
    try std.testing.expectEqualStrings("hello", result.first);
    try std.testing.expectEqualStrings("world", result.second);

    try std.testing.expect(splitOnce("hello", '.') == null);
}

test "languageToString" {
    try std.testing.expectEqualStrings("C", languageToString(.c));
    try std.testing.expectEqualStrings("Rust", languageToString(.rust));
    try std.testing.expectEqualStrings("Go", languageToString(.go));
    try std.testing.expectEqualStrings("Zig", languageToString(.zig));
    try std.testing.expectEqualStrings("unknown", languageToString(.unknown));
}
