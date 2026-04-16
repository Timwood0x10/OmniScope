//! FFI Boundary Detection Pass
//!
//! Detects and marks cross-language transitions in the call graph.
//! Integrates with the unified data flow architecture using DataFlowGraph.

const std = @import("std");
const c = @import("../../ir/llvm_raw.zig").c;

const PassContext = @import("../pass.zig").PassContext;
const PassKind = @import("../pass.zig").PassKind;
const DiagnosticWriter = @import("../pass.zig").DiagnosticWriter;

const Location = @import("../../diag/issue.zig").Location;
const FFIBoundary = @import("../../diag/issue.zig").FFIBoundary;
const BoundaryKind = @import("../../diag/issue.zig").FFIBoundary.BoundaryKind;
const Language = @import("../../diag/issue.zig").FFIBoundary.Language;

/// Error type for FFI boundary detection operations.
pub const FFIBoundaryError = error{
    /// Memory allocation failed.
    OutOfMemory,
    /// Module not available.
    NoModule,
};

/// FFI boundary detection pass.
///
/// Identifies cross-language transitions in the call graph and
/// marks them in the DataFlowGraph for downstream analysis.
///
/// Detection strategy:
/// - Analyzes function calls in the IR
/// - Classifies calls based on naming conventions and linkage
/// - Identifies language boundaries (e.g., Rust->C, Zig->C)
/// - Creates FFIBoundary entries in DataFlowGraph
pub const FFIBoundaryPass = struct {
    pub const name = "ffi-boundary";
    pub const kind = PassKind.foundation;
    pub const deps = &[_][]const u8{};

    /// Known FFI patterns for language identification
    const FFIPatterns = struct {
        /// Rust FFI function name patterns
        const rust_patterns = &[_][]const u8{
            "extern", // extern "C"
            "rust_", // Rust C ABI
            "_ZN", // Rust mangling
        };

        /// Zig FFI function name patterns
        const zig_patterns = &[_][]const u8{
            "extern", // extern functions
            "c_", // C API prefixes
        };

        /// C standard library functions (not FFI boundaries)
        const libc_patterns = &[_][]const u8{
            "malloc",
            "free",
            "printf",
            "scanf",
            "strcpy",
            "strcmp",
            "strlen",
            "memcpy",
            "memset",
            "exit",
            "abort",
        };

        /// Dangerous/suspicious FFI patterns
        const dangerous_patterns = &[_][]const u8{
            "system",
            "exec",
            "popen",
            "eval",
            "shell",
            "debug",
            "dump",
        };
    };

    /// Run FFI boundary detection
    pub fn run(ctx: *PassContext, diag: *DiagnosticWriter) FFIBoundaryError!void {
        if (ctx.module == null) {
            diag.warn("FFIBoundary: No module loaded, skipping analysis", .{});
            return;
        }

        // If FFIMatcher is available, create FFI boundaries from matches
        if (ctx.data_flow_graph.hasFFIMatcher()) {
            try ctx.data_flow_graph.createFFIBoundariesFromMatcher();
            diag.info("FFIBoundary: Created boundaries from FFIMatcher", .{});
        }

        const mod = ctx.module.?.raw;
        var func = c.LLVMGetFirstFunction(mod);
        if (@intFromPtr(func) == 0) {
            diag.info("FFIBoundary: No functions in module", .{});
            return;
        }

        var boundary_count: u32 = 0;
        var func_count: u32 = 0;

        while (@intFromPtr(func) != 0) : (func = c.LLVMGetNextFunction(func)) {
            func_count += 1;

            // Skip declarations (only analyze definitions)
            if (c.LLVMIsDeclaration(func) != 0) continue;

            // Analyze function for FFI calls
            boundary_count += try analyzeFunction(ctx, func, diag);
        }

        diag.info("FFIBoundary: Analyzed {} functions, found {} FFI boundaries", .{
            func_count,
            boundary_count,
        });
    }

    /// Analyze a single function for FFI boundaries
    fn analyzeFunction(ctx: *PassContext, func: c.LLVMValueRef, diag: *DiagnosticWriter) !u32 {
        var boundary_count: u32 = 0;
        var bb = c.LLVMGetFirstBasicBlock(func);
        while (@intFromPtr(bb) != 0) : (bb = c.LLVMGetNextBasicBlock(bb)) {
            var inst = c.LLVMGetFirstInstruction(bb);
            while (@intFromPtr(inst) != 0) : (inst = c.LLVMGetNextInstruction(inst)) {
                // Check for call instructions
                if (@intFromPtr(c.LLVMIsACallInst(inst)) != 0) {
                    if (try checkCallForFFI(ctx, inst, func, diag)) {
                        boundary_count += 1;
                    }
                }
            }
        }
        return boundary_count;
    }

    /// Check a call instruction for FFI boundary
    fn checkCallForFFI(
        ctx: *PassContext,
        inst: c.LLVMValueRef,
        caller_func: c.LLVMValueRef,
        diag: *DiagnosticWriter,
    ) !bool {
        const called_val = c.LLVMGetCalledValue(inst);
        if (@intFromPtr(called_val) == 0) return false;

        // Get function name
        const called_name_ptr = c.LLVMGetValueName(called_val);
        if (@intFromPtr(called_name_ptr) == 0) return false;
        const called_name = std.mem.span(called_name_ptr);

        // Skip libc functions (not true FFI boundaries)
        if (isLibcFunction(called_name)) {
            return false;
        }

        // Check if the called function is a declaration (external function)
        const is_external = c.LLVMIsDeclaration(called_val) != 0;

        // Identify the language boundary
        const caller_lang = identifyLanguage(caller_func);
        var callee_lang = identifyCalleeLanguage(called_name);

        // If it's an external function and not clearly identified, mark as unknown
        if (is_external and callee_lang == .unknown) {
            // External unknown functions are potential FFI boundaries
            callee_lang = .unknown;
        }

        // If it's a cross-language call or external unknown, create an FFI boundary
        if ((caller_lang != callee_lang and callee_lang != .unknown) or is_external) {
            const boundary_kind = classifyBoundaryKind(caller_lang, callee_lang);

            // Get caller function name
            const caller_name_ptr = c.LLVMGetValueName(caller_func);
            const caller_name = if (@intFromPtr(caller_name_ptr) != 0)
                std.mem.span(caller_name_ptr)
            else
                "unknown";

            // Create location
            const location = Location.init(caller_name);

            // Create FFI boundary
            const boundary = FFIBoundary.init(
                ctx.getNextId(),
                boundary_kind,
                caller_lang,
                callee_lang,
                called_name,
                location,
            );

            // Add to DataFlowGraph
            try ctx.addFFIBoundary(boundary);

            diag.info("FFI Boundary: {s} -> {s} ({s}) -> {s} ({s})", .{
                @tagName(caller_lang),
                caller_name,
                @tagName(boundary_kind),
                called_name,
                @tagName(callee_lang),
            });

            return true;
        }

        return false;
    }

    /// Identify the language of a function based on its characteristics
    fn identifyLanguage(func: c.LLVMValueRef) Language {
        const func_name_ptr = c.LLVMGetValueName(func);
        if (@intFromPtr(func_name_ptr) == 0) return .unknown;

        const func_name = std.mem.span(func_name_ptr);

        // Check for Rust patterns
        for (FFIPatterns.rust_patterns) |pattern| {
            if (std.mem.indexOf(u8, func_name, pattern) != null) {
                return .rust;
            }
        }

        // Check for Zig patterns (be more specific to avoid false positives)
        // Only mark as zig if we see clear Zig indicators
        var has_zig_indicator = false;
        for (FFIPatterns.zig_patterns) |pattern| {
            if (std.mem.indexOf(u8, func_name, pattern) != null) {
                // Check for additional Zig-specific patterns
                if (std.mem.indexOf(u8, func_name, "zig_") != null or
                    std.mem.indexOf(u8, func_name, "@") != null)
                {
                    has_zig_indicator = true;
                    break;
                }
            }
        }

        if (has_zig_indicator) {
            return .zig;
        }

        // Default to C (most common case for C ABI)
        return .c;
    }

    /// Identify the language of a called function based on its name
    fn identifyCalleeLanguage(func_name: []const u8) Language {
        // Check for Rust patterns
        for (FFIPatterns.rust_patterns) |pattern| {
            if (std.mem.indexOf(u8, func_name, pattern) != null) {
                return .rust;
            }
        }

        // Check for Zig patterns
        for (FFIPatterns.zig_patterns) |pattern| {
            if (std.mem.indexOf(u8, func_name, pattern) != null) {
                return .zig;
            }
        }

        // Check if it's an external/unknown function
        // (no specific language patterns)
        return .unknown;
    }

    /// Classify the boundary kind based on caller and callee languages
    fn classifyBoundaryKind(caller_lang: Language, callee_lang: Language) BoundaryKind {
        return switch (caller_lang) {
            .rust => switch (callee_lang) {
                .c => .rust_to_c,
                .zig => .external_unknown,
                else => .external_unknown,
            },
            .zig => switch (callee_lang) {
                .c => .zig_to_c,
                .rust => .external_unknown,
                else => .external_unknown,
            },
            .c => switch (callee_lang) {
                .rust => .c_to_rust,
                .zig => .c_to_zig,
                else => .external_unknown,
            },
            else => .external_unknown,
        };
    }

    /// Check if a function name is a libc function
    fn isLibcFunction(func_name: []const u8) bool {
        for (FFIPatterns.libc_patterns) |pattern| {
            if (std.mem.eql(u8, func_name, pattern)) {
                return true;
            }
        }
        return false;
    }

    /// Check if a function name represents a dangerous FFI pattern
    pub fn isDangerousPattern(func_name: []const u8) bool {
        for (FFIPatterns.dangerous_patterns) |pattern| {
            if (std.mem.indexOf(u8, func_name, pattern) != null) {
                return true;
            }
        }
        return false;
    }
};

// Unit tests

test "FFIBoundaryPass - name" {
    try std.testing.expectEqualStrings("ffi-boundary", FFIBoundaryPass.name);
}

test "FFIBoundaryPass - kind" {
    try std.testing.expectEqual(PassKind.foundation, FFIBoundaryPass.kind);
}

test "FFIBoundaryPass - deps" {
    try std.testing.expectEqual(@as(usize, 0), FFIBoundaryPass.deps.len);
}

test "FFIBoundaryPass - isDangerousPattern" {
    try std.testing.expect(FFIBoundaryPass.isDangerousPattern("system"));
    try std.testing.expect(FFIBoundaryPass.isDangerousPattern("exec_cmd"));
    try std.testing.expect(FFIBoundaryPass.isDangerousPattern("debug_dump"));
    try std.testing.expect(!FFIBoundaryPass.isDangerousPattern("safe_func"));
    try std.testing.expect(!FFIBoundaryPass.isDangerousPattern("print_message"));
}
