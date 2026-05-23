//! Free Validation Detection Pass
//!
//! Detects when free() is called on pointers that do not originate from
//! memory allocation functions. This can cause undefined behavior.
//!
//! Design principle: Only based on IR facts, no guessing.
//! - Track pointer origins (from_malloc, from_param, from_global, unknown)
//! - Check free() calls for valid origins
//! - Report violations with traceable reasoning

const std = @import("std");
const c = @import("../../../ir/llvm_raw.zig").c;

const PassContext = @import("../../pass.zig").PassContext;
const PassKind = @import("../../pass.zig").PassKind;
const DiagnosticWriter = @import("../../pass.zig").DiagnosticWriter;

const Location = @import("../../../diag/issue.zig").Location;
const Issue = @import("../../../diag/issue.zig").Issue;
const IssueKind = @import("../../../diag/issue.zig").IssueKind;
const Severity = @import("../../../diag/issue.zig").Severity;
const TraceEntry = @import("../../../diag/issue.zig").TraceEntry;
const ValueOrigin = @import("../ffi_semantics.zig").ValueOrigin;
const noise_filter = @import("../../../semantics/noise_filter.zig");
const rust_drop_semantics = @import("../../../semantics/rust_drop_semantics.zig");
const DebugInfoUtils = @import("../../../ir/debug_info.zig").DebugInfoUtils;
const ffi_utils = @import("../ffi_utils.zig");
const ptr_types = @import("../ptr_lifetime_types.zig");
const classify = @import("../ptr_lifetime_classify.zig");

/// Memory deallocation functions — basic memory deallocators for free validation.
/// NOTE: This is distinct from ptr_types.KNOWN_DEALLOCATORS.free_functions which
/// covers library-specific cleanup (sqlite3_free, curl_easy_cleanup, etc.).
pub const FREE_FUNCTIONS = &[_][]const u8{
    "free",           "dealloc",       "deallocate",   "operator delete", "operator delete[]",
    // Rust global deallocator intrinsics (substring-matched via isFreeFunction)
    "__rust_dealloc", "__rdl_dealloc", "__rg_dealloc",
};

/// Memory allocation functions — delegated to ptr_types (single source of truth).
pub const ALLOC_FUNCTIONS = ptr_types.HEAP_ALLOC_FUNCTIONS;

/// Free validation detection pass
///
/// This pass implements Rule 2 from go_noise.md:
/// Detect when free is called on non-malloc pointers.
pub const FreeValidationPass = struct {
    pub const name = "free-validation";
    pub const kind = PassKind.analysis;
    pub const deps = &[_][]const u8{ "danger-surface", "ptr-lifetime" };

    pub fn run(ctx: *PassContext, diag: *DiagnosticWriter) !void {
        if (ctx.module == null) return;
        // Runtime dependency validation: danger_surface must have populated relevant set.
        // If empty, DangerSurfacePass didn't run or found nothing — skip to avoid false positives.
        if (ctx.danger_surface_relevant.count() == 0) return;

        const mod = ctx.module.?.raw;
        var func = c.LLVMGetFirstFunction(mod);
        if (@intFromPtr(func) == 0) return;

        var issue_count: usize = 0;
        while (@intFromPtr(func) != 0) : (func = c.LLVMGetNextFunction(func)) {
            if (!ctx.isRelevantFunction(@as(u64, @intFromPtr(func)))) continue;
            // Function-level error isolation
            const count = analyzeFunction(ctx, func, diag) catch |err| {
                const func_name_raw = c.LLVMGetValueName(func);
                const func_name = if (func_name_raw != null) std.mem.span(func_name_raw) else "unknown";
                diag.warn("FreeValidation: skipped function due to error: {} ({s})", .{ err, func_name });
                ctx.recordDegradedFunction();
                continue;
            };
            issue_count += count;
        }

        if (issue_count > 0) {
            diag.info("[OMI-HIGH] FreeValidation: Found {} invalid free calls", .{issue_count});
        } else {
            diag.debug("FreeValidation: No invalid free calls found", .{});
        }
    }

    fn analyzeFunction(ctx: *PassContext, func: c.LLVMValueRef, diag: *DiagnosticWriter) !usize {
        var issue_count: usize = 0;

        // INTEGRATION: Three-layer noise filter (name + path)
        const func_name_ptr = c.LLVMGetValueName(func);
        if (@intFromPtr(func_name_ptr) == 0) return 0;
        const func_name = std.mem.span(func_name_ptr);
        const func_loc = DebugInfoUtils.getFunctionLocation(func);
        const classification = noise_filter.classifyFunctionFull(func_name, null, func_loc, null);
        if (!classification.origin.shouldReportByDefault()) return 0;

        // Track pointer origins within this function
        var pointer_origins = std.AutoHashMap(c.LLVMValueRef, PointerInfo).init(ctx.allocator);
        defer {
            // Free all allocated source_desc strings
            var iter = pointer_origins.iterator();
            while (iter.next()) |entry| {
                ctx.allocator.free(entry.value_ptr.source_desc);
            }
            pointer_origins.deinit();
        }

        // First pass: track function parameters as from_param
        {
            var param = c.LLVMGetFirstParam(func);

            var param_index: u32 = 0;
            while (@intFromPtr(param) != 0) : (param = c.LLVMGetNextParam(param)) {
                const desc = try std.fmt.allocPrint(ctx.allocator, "from parameter {d} in {s}", .{ param_index, func_name });
                // Use getOrPut to check if key exists and free old desc if needed
                const gop = try pointer_origins.getOrPut(param);
                if (gop.found_existing) {
                    ctx.allocator.free(gop.value_ptr.source_desc);
                }
                gop.value_ptr.* = .{
                    .origin = .from_param,
                    .source_inst = null,
                    .source_desc = desc,
                };
                param_index += 1;
            }
        }

        // Second pass: track instruction pointer origins
        var bb = c.LLVMGetFirstBasicBlock(func);
        while (@intFromPtr(bb) != 0) : (bb = c.LLVMGetNextBasicBlock(bb)) {
            var inst = c.LLVMGetFirstInstruction(bb);
            while (@intFromPtr(inst) != 0) : (inst = c.LLVMGetNextInstruction(inst)) {
                try trackPointerOrigin(ctx.allocator, inst, &pointer_origins);
            }
        }

        // Third pass: check free calls
        bb = c.LLVMGetFirstBasicBlock(func);
        while (@intFromPtr(bb) != 0) : (bb = c.LLVMGetNextBasicBlock(bb)) {
            var inst = c.LLVMGetFirstInstruction(bb);
            while (@intFromPtr(inst) != 0) : (inst = c.LLVMGetNextInstruction(inst)) {
                if (try checkFreeCall(ctx, inst, &pointer_origins, func, diag)) {
                    issue_count += 1;
                }
            }
        }

        return issue_count;
    }

    /// Information about a pointer's origin
    const PointerInfo = struct {
        /// Origin of the pointer
        origin: ValueOrigin,
        /// Source instruction (if from allocation)
        source_inst: ?c.LLVMValueRef,
        /// Description for trace
        source_desc: []const u8,
    };

    /// Track the origin of pointers
    fn trackPointerOrigin(
        allocator: std.mem.Allocator,
        inst: c.LLVMValueRef,
        pointer_origins: *std.AutoHashMap(c.LLVMValueRef, PointerInfo),
    ) !void {
        const opcode = c.LLVMGetInstructionOpcode(inst);

        switch (opcode) {
            // Allocation calls - mark as from_malloc
            c.LLVMCall => {
                const called = c.LLVMGetCalledValue(inst);
                if (@intFromPtr(called) != 0) {
                    const func_name_ptr = c.LLVMGetValueName(called);
                    if (@intFromPtr(func_name_ptr) != 0) {
                        const func_name = std.mem.span(func_name_ptr);

                        if (isAllocFunction(func_name)) {
                            const desc = try std.fmt.allocPrint(allocator, "from {s}()", .{func_name});
                            const gop = try pointer_origins.getOrPut(inst);
                            if (gop.found_existing) {
                                allocator.free(gop.value_ptr.source_desc);
                            }
                            gop.value_ptr.* = .{
                                .origin = .from_malloc,
                                .source_inst = inst,
                                .source_desc = desc,
                            };
                        } else if (isFFIBoundaryCall(func_name)) {
                            // FFI boundary call returning a pointer — cross-allocator risk
                            const desc = try std.fmt.allocPrint(allocator, "from FFI call {s}()", .{func_name});
                            const gop = try pointer_origins.getOrPut(inst);
                            if (gop.found_existing) {
                                allocator.free(gop.value_ptr.source_desc);
                            }
                            gop.value_ptr.* = .{
                                .origin = .from_ffi_call,
                                .source_inst = inst,
                                .source_desc = desc,
                            };
                        }
                    }
                }
            },

            // Load/Store - propagate origin (copy source_desc)
            c.LLVMLoad => {
                const ptr = c.LLVMGetOperand(inst, 0);
                if (pointer_origins.get(ptr)) |info| {
                    const desc = try allocator.dupe(u8, info.source_desc);
                    const gop = try pointer_origins.getOrPut(inst);
                    if (gop.found_existing) {
                        allocator.free(gop.value_ptr.source_desc);
                    }
                    gop.value_ptr.* = .{
                        .origin = info.origin,
                        .source_inst = info.source_inst,
                        .source_desc = desc,
                    };
                }
            },

            // GEP - propagate origin (copy source_desc)
            c.LLVMGetElementPtr => {
                const ptr = c.LLVMGetOperand(inst, 0);
                if (pointer_origins.get(ptr)) |info| {
                    const desc = try allocator.dupe(u8, info.source_desc);
                    const gop = try pointer_origins.getOrPut(inst);
                    if (gop.found_existing) {
                        allocator.free(gop.value_ptr.source_desc);
                    }
                    gop.value_ptr.* = .{
                        .origin = info.origin,
                        .source_inst = info.source_inst,
                        .source_desc = desc,
                    };
                }
            },

            // BitCast - propagate origin (copy source_desc)
            c.LLVMBitCast => {
                const ptr = c.LLVMGetOperand(inst, 0);
                if (pointer_origins.get(ptr)) |info| {
                    const desc = try allocator.dupe(u8, info.source_desc);
                    const gop = try pointer_origins.getOrPut(inst);
                    if (gop.found_existing) {
                        allocator.free(gop.value_ptr.source_desc);
                    }
                    gop.value_ptr.* = .{
                        .origin = info.origin,
                        .source_inst = info.source_inst,
                        .source_desc = desc,
                    };
                }
            },

            else => {},
        }
    }

    /// Determine if a free/dealloc call is safe in its FFI context.
    /// Centralizes Rust ownership model awareness: when Rust code uses
    /// __rust_dealloc on a pointer from Box::into_raw(), it's intentional
    /// ownership reclamation — not a bug.
    ///
    /// SECURITY POLICY (2026-05-05 tightened):
    /// For C/C++: Established conventions allow broader trust (global statics, well-known wrappers).
    /// For Rust/Zig: Stricter — these languages have ownership systems; if code bypasses them
    /// via FFI, we require explicit safety proof (null checks, RAII, refcount), not assumptions.
    fn isFreeSafe(free_func: []const u8, origin: ValueOrigin, source_desc: []const u8) bool {
        // Rust Drop Semantics: drop glue and drop-chain deallocs are
        // compiler-generated implicit destructors — NOT bugs.
        // E.g., drop_in_place<T> and __rust_dealloc within a drop chain
        // are safe because they represent automatic scope-end cleanup.
        if (rust_drop_semantics.isImplicitDropFree(free_func, true, false)) return true;
        // Rust dealloc on param: normal ownership transfer (caller owns → callee frees)
        if (origin == .from_param and isRustDeallocFunction(free_func)) return true;
        // into_raw + matching Rust dealloc: correct ownership reclamation
        if (source_desc.len > 0 and isPossibleIntoRawOutput(source_desc) and isRustDeallocFunction(free_func)) return true;
        // FFI-sourced pointer freed by known safe wrappers only.
        // Previously exempted ALL non-Rust/non-standard frees (too broad — missed Rust FFI bugs).
        // Now restricted to well-known language-specific deallocators:
        //   - g_free (GLib/GObject) pairs with g_malloc/g_new
        //   - CFRelease/CFAutorelease (CoreFoundation) pairs with Create/Copy
        //   - PyObject_Free (Python C API) pairs with PyObject_Malloc
        //   - cudaFree (CUDA runtime) pairs with cudaMalloc
        //   - vkFreeMemory (Vulkan API) pairs with vkAllocateMemory
        //   - ID3D12Device_Release (DirectX 12) pairs with CreateDevice
        //   - Platform-specific: VirtualFree/HeapFree (Windows), munmap (POSIX)
        //
        // NOTE: .from_global origin is intentionally NOT auto-trusted here.
        // Global pointers in Rust/Zig FFI context are suspicious — they may indicate
        // a static that was allocated in one language and freed in another without
        // proper coordination. Flag for manual review unless proven safe.
        if (origin == .from_ffi_call and !isRustDeallocFunction(free_func) and
            !std.mem.eql(u8, free_func, "free"))
        {
            const known_safe_wrappers = [_][]const u8{
                "g_free",        "CFRelease",            "CFAutorelease",
                "PyObject_Free", "PyMem_Free",           "cudaFree",
                "vkFreeMemory",  "ID3D12Device_Release", "VirtualFree",
                "HeapFree",      "munmap",               "mmap_free",
                "objc_release",  "NSDeallocateObject",   "CoTaskMemFree",
                "SysFreeString",
            };
            for (known_safe_wrappers) |wrapper| {
                if (std.mem.eql(u8, free_func, wrapper)) return true;
            }
            // Default: do NOT exempt — flag as suspicious for manual review
        }
        // All other origins (.from_global, .unknown, etc.) default to unsafe.
        // This is intentional: if we can't prove it's safe, flag it.
        return false;
    }

    /// Check if a free call is valid
    fn checkFreeCall(
        ctx: *PassContext,
        inst: c.LLVMValueRef,
        pointer_origins: *const std.AutoHashMap(c.LLVMValueRef, PointerInfo),
        caller_func: c.LLVMValueRef,
        diag: *DiagnosticWriter,
    ) !bool {
        const opcode = c.LLVMGetInstructionOpcode(inst);

        if (opcode != c.LLVMCall) return false;

        const called = c.LLVMGetCalledValue(inst);
        if (@intFromPtr(called) == 0) return false;

        const callee_name_ptr = c.LLVMGetValueName(called);
        if (@intFromPtr(callee_name_ptr) == 0) return false;

        const callee_name = std.mem.span(callee_name_ptr);
        if (!isFreeFunction(callee_name)) return false;

        // Get the pointer being freed
        const ptr_arg = c.LLVMGetOperand(inst, 0);
        if (@intFromPtr(ptr_arg) == 0) return false;

        // Check origin
        const origin_info = pointer_origins.get(ptr_arg);
        const origin = if (origin_info) |info| info.origin else .unknown;

        // Only report for clearly invalid origins (not unknown - may be cross-function alloc)
        // unknown origin is skipped because allocation may have happened in another function
        //
        // ValueOrigin enum coverage (ffi_semantics.zig):
        //   - .from_param / .from_global / .from_constant → invalid free (report)
        //   - .from_malloc → valid (skip)
        //   - .unknown → cross-function alloc (skip to avoid false positives)
        //
        // NOTE: This switch is exhaustive for all ValueOrigin variants.
        // The Zig compiler will emit a compile error if new enum values are added
        // without updating this switch, ensuring completeness at compile time.
        switch (origin) {
            .from_param => {
                const src = if (origin_info) |info| info.source_desc else "";
                if (isFreeSafe(callee_name, origin, src)) return false;
                // FIX: free() on a function parameter is NOT necessarily invalid.
                // In C/C++, ownership transfer (caller malloc → callee free) is a
                // standard pattern. The real invalid_free is free(stack_var) or
                // free(global_var), not free(heap_pointer_passed_as_param).
                // Our origin tracking loses "from_malloc" when the pointer flows
                // through memcpy/store/load, causing from_param false positives.
                // Only report if the free function is NOT standard C free/dealloc
                // (e.g., __rust_dealloc on a C-allocated param IS a cross-allocator bug).
                if (std.mem.eql(u8, callee_name, "free") or
                    std.mem.startsWith(u8, callee_name, "operator delete"))
                {
                    return false;
                }
                try reportInvalidFree(ctx, caller_func, callee_name, ptr_arg, origin, origin_info, diag);
                return true;
            },
            .from_global, .from_constant => {
                try reportInvalidFree(ctx, caller_func, callee_name, ptr_arg, origin, origin_info, diag);
                return true;
            },
            .from_ffi_call => {
                const src = if (origin_info) |info| info.source_desc else "";
                if (isCrossAllocatorFree(.from_ffi_call, src, callee_name)) {
                    try reportInvalidFree(ctx, caller_func, callee_name, ptr_arg, origin, origin_info, diag);
                    return true;
                }
                if (isFreeSafe(callee_name, origin, src)) return false;
                // P1 FIX: Standard C free()/operator delete on an FFI-sourced
                // pointer is NOT necessarily invalid. If cross-allocator check
                // already passed (e.g., C/C++ FFI returning heap memory freed
                // by C free), this is a normal ownership transfer pattern.
                // Only flag when using a non-standard deallocator that might
                // mismatch the FFI source's allocator.
                if (std.mem.eql(u8, callee_name, "free") or
                    std.mem.startsWith(u8, callee_name, "operator delete"))
                {
                    return false;
                }
                try reportInvalidFree(ctx, caller_func, callee_name, ptr_arg, origin, origin_info, diag);
                return true;
            },
            .from_malloc => {
                const src = if (origin_info) |info| info.source_desc else "";
                if (isCrossAllocatorFree(.from_malloc, src, callee_name)) {
                    try reportInvalidFree(ctx, caller_func, callee_name, ptr_arg, origin, origin_info, diag);
                    return true;
                }
                if (isFreeSafe(callee_name, origin, src)) return false;
                // P1 FIX: free() on malloc'd memory is always valid (C/C++ pattern).
                // The cross-allocator check above already catches the real bugs
                // (malloc + __rust_dealloc, __rust_alloc + free). Only flag
                // if using a clearly mismatched deallocator on malloc'd memory.
                if (std.mem.eql(u8, callee_name, "free") or
                    std.mem.startsWith(u8, callee_name, "operator delete"))
                {
                    return false;
                }
                if (src.len > 0 and !isFreeSafe(callee_name, origin, src)) {
                    try reportInvalidFree(ctx, caller_func, callee_name, ptr_arg, origin, origin_info, diag);
                    return true;
                }
            },
            .unknown => {},
        }

        return false;
    }

    /// Check if function is a Rust deallocation function.
    /// Only matches actual Rust dealloc intrinsics (NOT general drop glue).
    /// Drop glue includes destructors that don't necessarily deallocate memory.
    fn isRustDeallocFunction(func_name: []const u8) bool {
        const rust_dealloc_patterns = [_][]const u8{
            "__rustc__rustc_dealloc",
            "__rust_dealloc",
        };
        for (rust_dealloc_patterns) |p| {
            if (std.mem.indexOf(u8, func_name, p) != null) return true;
        }
        return false;
    }

    /// Check if callee is an FFI boundary function (non-Rust-mangled name).
    /// Used to detect pointers returned from C/external functions, which carry
    /// cross-allocator free risk when passed to libc::free or __rust_dealloc.
    ///
    /// IMPORTANT: Standard C library functions and compiler intrinsics are NOT
    /// FFI boundary calls — they are same-language runtime functions. Including
    /// them would cause massive false positives (every malloc pointer treated
    /// as "FFI-originated" when freed by free()).
    ///
    /// Future enhancement: use ctx.getCrossEdgeByCallee(callee) != null
    /// to cover unmangled Rust wrappers (e.g., test_double_free_box).
    /// Requires refactoring this fn to accept PassContext parameter.
    fn isFFIBoundaryCall(func_name: []const u8) bool {
        if (func_name.len < 2) return false;

        // Rust-internal functions: _ZN (legacy), _RNv / _R (v0 mangling)
        const rust_prefixes = [_][]const u8{ "_ZN", "_RNv", "_R" };
        for (rust_prefixes) |prefix| {
            if (std.mem.startsWith(u8, func_name, prefix)) return false;
        }

        // LLVM intrinsics
        if (std.mem.startsWith(u8, func_name, "llvm.")) return false;

        // Rust compiler intrinsics (__rust_alloc, __rust_dealloc, etc.)
        if (std.mem.startsWith(u8, func_name, "__rust_")) return false;
        if (std.mem.startsWith(u8, func_name, "__rdl_")) return false;
        if (std.mem.startsWith(u8, func_name, "__rg_")) return false;

        // Standard C library alloc/free functions — these are NOT FFI boundaries.
        // They are same-language runtime calls; cross-allocator detection is
        // handled separately by isCrossAllocatorFree().
        const libc_functions = [_][]const u8{
            "malloc",        "calloc",         "realloc",  "free",
            "aligned_alloc", "posix_memalign", "memalign", "pvalloc",
            "valloc",        "strdup",         "strndup",
        };
        for (libc_functions) |libc_fn| {
            if (std.mem.eql(u8, func_name, libc_fn)) return false;
        }

        // C++ operator new/delete — same-language runtime, not FFI boundary
        if (std.mem.startsWith(u8, func_name, "operator new")) return false;
        if (std.mem.startsWith(u8, func_name, "operator delete")) return false;

        // Common C runtime wrappers that are NOT cross-language boundaries
        if (std.mem.startsWith(u8, func_name, "memcpy")) return false;
        if (std.mem.startsWith(u8, func_name, "memset")) return false;
        if (std.mem.startsWith(u8, func_name, "memmove")) return false;
        if (std.mem.startsWith(u8, func_name, "__cxa_")) return false;
        if (std.mem.startsWith(u8, func_name, "_Unwind_")) return false;

        return true;
    }

    /// Check if a free call crosses allocator boundaries.
    /// Returns true when memory from one runtime's allocator is freed
    /// by a different runtime's deallocator — almost always a bug.
    fn isCrossAllocatorFree(alloc_origin: ValueOrigin, source_desc: []const u8, free_func: []const u8) bool {
        const is_rust_free = isRustDeallocFunction(free_func);
        const is_c_free = std.mem.eql(u8, free_func, "free") or
            std.mem.eql(u8, free_func, "kfree") or
            std.mem.eql(u8, free_func, "g_free");

        if (alloc_origin == .from_malloc) {
            const is_rust_alloc = std.mem.indexOf(u8, source_desc, "__rust_alloc") != null or
                std.mem.indexOf(u8, source_desc, "__rdl_alloc") != null or
                std.mem.indexOf(u8, source_desc, "__rg_alloc") != null;
            if (is_rust_alloc and is_c_free) return true;
            if (!is_rust_alloc and is_rust_free) return true;
        }

        if (alloc_origin == .from_ffi_call) {
            const is_rust_source = std.mem.indexOf(u8, source_desc, "__rust") != null or
                std.mem.indexOf(u8, source_desc, "_ZN") != null;
            if (is_rust_source and is_c_free) return true;
        }

        return false;
    }

    /// Check if the pointer may originate from Rust's into_raw() call.
    /// into_raw transfers ownership to the caller — freeing with anything
    /// other than the correct Rust deallocator is undefined behavior.
    fn isPossibleIntoRawOutput(source_desc: []const u8) bool {
        const into_raw_patterns = [_][]const u8{
            "into_raw",      "into_raw_parts",
            "Box::into_raw",
        };
        for (into_raw_patterns) |pat| {
            if (std.mem.indexOf(u8, source_desc, pat) != null) return true;
        }
        return false;
    }

    /// Check if function is a free function.
    /// Uses exact match + endsWith to avoid FP like 'my_custom_free' matching 'free'.
    fn isFreeFunction(func_name: []const u8) bool {
        return classify.isFreeFunction(func_name);
    }

    /// Check if function is an allocation function.
    /// Uses exact match + endsWith to avoid FP like 'my_custom_allocator' matching 'alloc'.
    fn isAllocFunction(func_name: []const u8) bool {
        for (ALLOC_FUNCTIONS) |alloc_func| {
            if (functionNameMatches(func_name, alloc_func)) {
                return true;
            }
        }
        return false;
    }

    /// Match strategy: exact equality OR suffix match.
    /// Prevents substring FP (e.g., 'my_custom_free' ≠ 'free')
    /// while still catching mangled names like '_ZN...freeEv'.
    fn functionNameMatches(func_name: []const u8, pattern: []const u8) bool {
        if (std.mem.eql(u8, func_name, pattern)) return true;
        if (std.mem.endsWith(u8, func_name, pattern)) return true;
        return false;
    }

    /// Report invalid free call
    fn reportInvalidFree(
        ctx: *PassContext,
        caller_func: c.LLVMValueRef,
        free_func_name: []const u8,
        ptr_arg: c.LLVMValueRef,
        origin: ValueOrigin,
        origin_info: ?PointerInfo,
        diag: *DiagnosticWriter,
    ) !void {
        const caller_name_ptr = c.LLVMGetValueName(caller_func);
        const caller_name = if (@intFromPtr(caller_name_ptr) != 0)
            std.mem.span(caller_name_ptr)
        else
            "unknown";

        const location = Location.init(caller_name);

        // E2-2a: Alias closure severity upgrade — if the freed pointer reaches
        // FFI boundaries through alias chains, this is a cross-language memory error.
        const ptr_val: u64 = @intFromPtr(ptr_arg);
        const reaches_ffi = ctx.isOnDangerPathFull(ptr_val);
        const base_confidence: f32 = if (reaches_ffi) 0.85 else 0.75;
        const severity: Severity = if (reaches_ffi) .critical else .high;

        // Build trace for reasoning path
        const trace = try ctx.allocator.alloc(TraceEntry, 3);
        trace[0] = TraceEntry.init("Free called on non-heap pointer");
        trace[1] = try createOriginTraceEntry(ctx.allocator, origin, origin_info);
        trace[2] = try createFreeTraceEntry(ctx.allocator, free_func_name);

        const origin_str = switch (origin) {
            .from_param => "function parameter",
            .from_global => "global variable",
            .from_constant => "constant",
            .unknown => "unknown source",
            else => "non-heap source",
        };

        const ffi_note = if (reaches_ffi) " [cross-FFI alias detected]" else "";

        const message = try std.fmt.allocPrint(
            ctx.allocator,
            "{s}() called on {s} pointer (confidence: {d:.2}%{s})",
            .{ free_func_name, origin_str, base_confidence, ffi_note },
        );

        var issue = Issue.initWithTrace(
            .invalid_free,
            message,
            location,
            severity,
            base_confidence,
            trace,
        );
        errdefer issue.deinit(ctx.allocator);

        try ctx.addIssue(&issue);

        const omi_prefix = if (severity == .critical) "[OMI-CRITICAL] " else "[OMI-HIGH] ";
        diag.warn("{s}Invalid {s} on {s} pointer in function: {s}{s}", .{ omi_prefix, free_func_name, origin_str, caller_name, ffi_note });
    }

    /// Create trace entry for pointer origin
    fn createOriginTraceEntry(
        allocator: std.mem.Allocator,
        origin: ValueOrigin,
        origin_info: ?PointerInfo,
    ) !TraceEntry {
        const desc = if (origin_info) |info|
            try std.fmt.allocPrint(allocator, "Pointer origin: {s}", .{info.source_desc})
        else switch (origin) {
            .from_param => try allocator.dupe(u8, "Pointer origin: function parameter"),
            .from_global => try allocator.dupe(u8, "Pointer origin: global variable"),
            .from_constant => try allocator.dupe(u8, "Pointer origin: constant value"),
            .unknown => try allocator.dupe(u8, "Pointer origin: unknown"),
            else => try allocator.dupe(u8, "Pointer origin: non-heap source"),
        };
        return TraceEntry.initOwned(desc);
    }

    /// Create trace entry for free call
    fn createFreeTraceEntry(allocator: std.mem.Allocator, func_name: []const u8) !TraceEntry {
        const desc = try std.fmt.allocPrint(
            allocator,
            "Passed to {s}() which requires heap-allocated pointer",
            .{func_name},
        );
        return TraceEntry.initOwned(desc);
    }
};

test "FreeValidationPass - name and kind" {
    try std.testing.expectEqualStrings("free-validation", FreeValidationPass.name);
    try std.testing.expectEqual(PassKind.analysis, FreeValidationPass.kind);
}

test "FreeValidationPass - isFreeFunction" {
    try std.testing.expect(FreeValidationPass.isFreeFunction("free"));
    try std.testing.expect(FreeValidationPass.isFreeFunction("dealloc"));
    try std.testing.expect(!FreeValidationPass.isFreeFunction("malloc"));
    try std.testing.expect(!FreeValidationPass.isFreeFunction("printf"));
}

test "FreeValidationPass - isAllocFunction" {
    try std.testing.expect(FreeValidationPass.isAllocFunction("malloc"));
    try std.testing.expect(FreeValidationPass.isAllocFunction("calloc"));
    try std.testing.expect(!FreeValidationPass.isAllocFunction("free"));
    try std.testing.expect(!FreeValidationPass.isAllocFunction("printf"));
}
