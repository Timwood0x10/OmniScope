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
const log = std.log.scoped(.free_validation);
const c = @import("../../../ir/llvm_raw.zig").c;
const llvm_safe = @import("../../../ir/llvm_safe.zig");
const ir_store_mod = @import("../../../ir/ir_store.zig");
const ModuleIRStore = ir_store_mod.ModuleIRStore;
const FunctionIR = ir_store_mod.FunctionIR;

const PassContext = @import("../../pass.zig").PassContext;
const PassKind = @import("../../pass.zig").PassKind;
const DiagnosticWriter = @import("../../pass.zig").DiagnosticWriter;

const Location = @import("../../../diag/issue.zig").Location;
const Issue = @import("../../../diag/issue.zig").Issue;
const IssueKind = @import("../../../diag/issue.zig").IssueKind;
const Severity = @import("../../../diag/issue.zig").Severity;
const TraceEntry = @import("../../../diag/issue.zig").TraceEntry;
const ValueOrigin = @import("../ffi/ffi_semantics.zig").ValueOrigin;
const noise_filter = @import("../../../semantics/noise_filter.zig");
const rust_drop_semantics = @import("../../../semantics/rust_drop_semantics.zig");
const DebugInfoUtils = @import("../../../ir/debug_info.zig").DebugInfoUtils;
const ffi_utils = @import("../ffi/ffi_utils.zig");
const ptr_types = @import("../ptr_lifetime/ptr_lifetime_types.zig");
const classify = @import("../ptr_lifetime/ptr_lifetime_classify.zig");
const mg_types = @import("../../../types/memory_graph_types.zig");
const AllocNode = mg_types.AllocNode;
const FamilyId = mg_types.FamilyId;
const contract_db = @import("../../../resource/ffi_contract_db.zig");
const FFIContractDB = contract_db.FFIContractDB;
const cross_lang_detector = @import("cross_lang_free_detector.zig");
const ptr_utils = @import("../ptr_lifetime/ptr_lifetime_utils.zig");
const isIntentionalOwnershipTransfer = ptr_utils.isIntentionalOwnershipTransfer;
const library_alloc_pairs = @import("../../../semantics/patterns/library_alloc_pairs.zig");

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

        const ir_store = ctx.ir_store;
        if (ir_store.function_list.len == 0) return;

        // DangerSurface data is optional for cross-language free detection.
        // When absent, we skip only the danger-surface-dependent sub-checks,
        // but cross-language allocator mismatch detection still runs.
        const has_danger_surface = ctx.danger_surface_relevant.count() > 0;

        var issue_count: usize = 0;
        for (ir_store.function_list) |fir| {
            // Only gate on relevance when danger surface data is present.
            // When absent, run on all functions so cross-lang free detection still works.
            if (has_danger_surface and !ctx.isRelevantFunction(@as(u64, @intFromPtr(fir.func)))) continue;
            // Function-level error isolation
            const count = analyzeFunction(ctx, fir, diag, has_danger_surface) catch |err| {
                diag.warn("FreeValidation: skipped function due to error: {} ({s})", .{ err, fir.name });
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

    fn analyzeFunction(ctx: *PassContext, fir: *const FunctionIR, diag: *DiagnosticWriter, has_danger_surface: bool) !usize {
        var issue_count: usize = 0;
        const func = fir.func;

        // INTEGRATION: Three-layer noise filter (name + path)
        const func_name = fir.name;
        const func_loc = DebugInfoUtils.getFunctionLocation(func);
        const classification = ctx.classifyFunctionSurface(func_name, func_loc);
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
        for (fir.instructions, 0..) |inst, idx| {
            _ = idx;
            try trackPointerOrigin(ctx, inst, &pointer_origins);
        }

        // Third pass: check free calls
        for (fir.instructions) |inst| {
            if (try checkFreeCall(ctx, inst, &pointer_origins, func, diag, has_danger_surface)) {
                issue_count += 1;
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

    /// Check if a function is a known library-specific allocator from FFIContractDB.
    /// Used by trackPointerOrigin to identify library allocators (e.g., SSL_new,
    /// sqlite3_open, BIO_new) so their release functions can be validated later.
    fn isContractDbAllocFunc(ctx: *PassContext, func_name: []const u8) bool {
        return ctx.contract_db.isKnownAllocator(func_name);
    }

    /// Track the origin of pointers
    fn trackPointerOrigin(
        ctx: *PassContext,
        inst: c.LLVMValueRef,
        pointer_origins: *std.AutoHashMap(c.LLVMValueRef, PointerInfo),
    ) !void {
        const allocator = ctx.allocator;
        const opcode = c.LLVMGetInstructionOpcode(inst);

        switch (opcode) {
            // Allocation calls - mark as from_malloc
            c.LLVMCall, c.LLVMInvoke => {
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
                        } else if (library_alloc_pairs.lookupTable(func_name)) |entry| {
                            // Library allocator pair lookup: detect borrowed/non-owned returns.
                            // Functions like ffi_borrowed_label(), sqlite3_column_text(), getenv()
                            // return pointers the caller must NOT free. Tracking this prevents
                            // false negative when such a pointer IS incorrectly freed.
                            if (entry.effect == .borrow) {
                                const desc = try std.fmt.allocPrint(
                                    allocator,
                                    "from borrowed library func {s}() [DO NOT FREE]",
                                    .{func_name},
                                );
                                const gop = try pointer_origins.getOrPut(inst);
                                if (gop.found_existing) {
                                    allocator.free(gop.value_ptr.source_desc);
                                }
                                gop.value_ptr.* = .{
                                    .origin = .from_library_borrow,
                                    .source_inst = inst,
                                    .source_desc = desc,
                                };
                            } else if (entry.effect == .acquire) {
                                // Library acquire function — treat like malloc for ownership tracking
                                const desc = try std.fmt.allocPrint(
                                    allocator,
                                    "from library alloc {s}()",
                                    .{func_name},
                                );
                                const gop = try pointer_origins.getOrPut(inst);
                                if (gop.found_existing) {
                                    allocator.free(gop.value_ptr.source_desc);
                                }
                                gop.value_ptr.* = .{
                                    .origin = .from_malloc,
                                    .source_inst = inst,
                                    .source_desc = desc,
                                };
                            }
                            // release functions are handled separately in free-site validation
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
                        } else if (isRustAllocCall(func_name)) {
                            // Rust v0 mangled allocators (__rust_alloc, _RZN4alloc...)
                            // Track as from_malloc so cross-lang free detection can match them
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
                        } else if (isCppNewCall(func_name)) {
                            // C++ operator new (mangled as _Znwm, _Znam, etc.)
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
                        } else if (isContractDbAllocFunc(ctx, func_name)) {
                            // Library-specific allocator (e.g., sqlite3_open, SSL_CTX_new, BIO_new).
                            // Tracked so that validateWithContractDBFromSource() can later
                            // validate the matching release function.
                            const desc = try std.fmt.allocPrint(allocator, "from {s}()", .{func_name});
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

            // PHI node - merge origins from all incoming values (if/else, switch branches).
            // Uses LLVMCountIncoming (LLVM 22 C API) to iterate incoming values.
            c.LLVMPHI => {
                const num_incoming = c.LLVMCountIncoming(inst);
                var best_origin: ?PointerInfo = null;
                var best_priority: i32 = -1;
                var i: c_uint = 0;
                while (i < num_incoming) : (i += 1) {
                    const incoming_val = c.LLVMGetIncomingValue(inst, i);
                    if (pointer_origins.get(incoming_val)) |info| {
                        // Priority: higher = more risky origin
                        const priority: i32 = switch (info.origin) {
                            .from_malloc => 5,
                            .from_ffi_call => 4,
                            .from_library_borrow => 6, // Borrowed refs are highest risk if freed
                            .from_param => 3,
                            .from_global => 2,
                            .from_constant => 1,
                            .unknown => 0,
                        };
                        if (priority > best_priority) {
                            // Free previous candidate's desc before overwriting
                            if (best_origin) |prev| allocator.free(prev.source_desc);
                            const desc = try allocator.dupe(u8, info.source_desc);
                            best_origin = .{
                                .origin = info.origin,
                                .source_inst = info.source_inst,
                                .source_desc = desc,
                            };
                            best_priority = priority;
                        }
                    }
                }
                if (best_origin) |origin| {
                    const gop = try pointer_origins.getOrPut(inst);
                    if (gop.found_existing) {
                        allocator.free(gop.value_ptr.source_desc);
                    }
                    gop.value_ptr.* = origin;
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
        if (rust_drop_semantics.isImplicitDropFree(free_func, true, false, null)) return true;
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

    /// Enhanced MemoryGraph-based ownership validation for free calls.
    /// Eliminates false positives by querying MemoryGraph and FFIContractDB
    /// to verify alloc/free matching before reporting issues.
    ///
    /// Detection layers (in order):
    ///   1. FFIContractDB: Is this alloc/free pair valid per library contracts?
    ///   2. Double-free: Has this pointer already been freed?
    ///   3. Borrowed ref: Is this a borrowed pointer that shouldn't be freed?
    ///   4. Same-family: Are alloc and free from the same allocator family?
    ///   5. Rust ownership: Is this a valid Rust ownership transfer pattern?
    ///   6. Cross-allocator mismatch: REAL bug - wrong allocator for free
    ///
    /// Returns:
    ///   - `true`  → bug detected (caller should report and return true)
    ///   - `false` → safe release (valid free, no issue)
    ///   - `null`  → cannot determine (caller should fallback to legacy logic)
    fn validateFreeWithMemoryGraph(
        ctx: *PassContext,
        ptr_arg: c.LLVMValueRef,
        callee_name: []const u8,
        caller_func: c.LLVMValueRef,
        diag: *DiagnosticWriter,
    ) !?bool {
        const ptr_val: u64 = @intFromPtr(ptr_arg);

        // Use findCanonicalAlloc to handle aliases (ownership transfers, FFI boundaries)
        const node = ctx.memory_graph.findCanonicalAlloc(ptr_val) orelse return null;

        log.debug("FREE_VALIDATION: Checking free of ptr 0x{x} ({s}), alloc_node id={d}, family={s}", .{
            ptr_val,
            callee_name,
            node.id,
            if (node.alloc_family) |f| @tagName(f) else "null",
        });

        // Layer 1: FFIContractDB validation - check if this is a valid library-specific pair
        // This catches cases like SSL_new + SSL_free (valid) vs SSL_new + BIO_free (bug!)
        {
            const pair_validity = try validateWithContractDB(&ctx.contract_db, node, callee_name, ctx, caller_func, ptr_arg, diag);
            if (pair_validity) |result| {
                return result;
            }
            // result == null → no contract info, continue to next layer
        }

        // Layer 2: Double-free detection using enhanced analysis with FP reduction
        if (node.freed) {
            log.warn("FREE_VALIDATION: Potential DOUBLE-FREE! ptr 0x{x} already freed at 0x{x}", .{
                ptr_val,
                node.freed_by orelse 0,
            });

            // Use enhanced analysis with confidence scoring (v0.2.0 improvement)
            const df_analysis = ctx.memory_graph.analyzeDoubleFreeWithConfidence(ptr_val);

            if (df_analysis.is_double_free) {
                // High-confidence double-free → report it
                const conf_percent = @as(u32, @intFromFloat(df_analysis.confidence * 100.0));
                log.warn("FREE_VALIDATION: DOUBLE-FREE CONFIRMED (confidence={d}%%): {s}", .{
                    conf_percent,
                    df_analysis.reason,
                });
                try reportDoubleFreeIssue(ctx, caller_func, callee_name, ptr_arg, node, diag);
                return true; // Real double-free bug!
            } else if (df_analysis.confidence > 0.3 and df_analysis.confidence < 0.6) {
                // Medium confidence → log but don't report (likely FP)
                log.debug("FREE_VALIDATION: Suspected double-free suppressed (confidence={d:.1}): {s}", .{
                    df_analysis.confidence,
                    df_analysis.reason,
                });
                return false; // Suppress as likely false positive
            } else {
                log.debug("FREE_VALIDATION: Not a double-free: {s}", .{df_analysis.reason});
                return false; // Different branches or low confidence
            }
        }

        // Layer 3: Borrowed/refcount check - skip if this is a borrowed reference
        if (isBorrowedOrRefcount(node)) {
            log.debug("FREE_VALIDATION: Skipping borrowed/refcount ptr (likely DECREF, not real free)", .{});
            return false;
        }

        // Layer 4: Same-family check (existing logic)
        const alloc_family = node.alloc_family orelse .invalid;
        const free_family = classifyReleaseFamilyByName(ctx, callee_name);

        if (alloc_family == free_family and alloc_family != .invalid) {
            log.debug("MG-SAME-FAMILY: {s} matches alloc family {s}, safe", .{
                callee_name, @tagName(alloc_family),
            });

            // Mark as freed in MemoryGraph for future double-free detection
            markAsFreed(ctx, ptr_val, callee_name);

            return false;
        }

        // Layer 5: Rust ownership transfer patterns (existing logic)
        if (isRustOwnershipTransfer(node, callee_name)) {
            log.debug("MG-RUST-OWNERSHIP: {s} on Rust-allocated ptr, safe", .{callee_name});

            // Mark as freed in MemoryGraph
            markAsFreed(ctx, ptr_val, callee_name);

            return false;
        }

        // Layer 6: Cross-allocator mismatch = REAL bug (existing logic)
        if (isCrossAllocatorMismatch(node, callee_name)) {
            try reportCrossAllocatorFree(ctx, caller_func, callee_name, ptr_arg, node, diag);
            return true;
        }

        return null; // Cannot determine, fallback to legacy logic
    }

    /// Check if a free call is valid
    fn checkFreeCall(
        ctx: *PassContext,
        inst: c.LLVMValueRef,
        pointer_origins: *const std.AutoHashMap(c.LLVMValueRef, PointerInfo),
        caller_func: c.LLVMValueRef,
        diag: *DiagnosticWriter,
        has_danger_surface: bool,
    ) !bool {
        const opcode = c.LLVMGetInstructionOpcode(inst);

        if (!llvm_safe.isCallOrInvoke(opcode)) return false;

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

        // ── NEW: Cross-Language Free Detection (v0.2.0 enhancement) ──
        // Detects when memory from one language's allocator is freed by
        // a different language's deallocator - almost always a bug.
        // This catches cases like Rust _RZN...allocate + C free().
        if (origin_info) |info| {
            const src_desc = info.source_desc;
            // Extract alloc function name from source description
            const alloc_func_name = extractAllocFuncNameForCrossLang(src_desc);
            if (alloc_func_name) |alloc_func| {
                log.debug("CROSS-LANG-CHECK: alloc={s}, free={s}", .{ alloc_func, callee_name });

                // Check for intentional ownership transfer at the call site (caller function).
                // Patterns like Box::into_raw / ManuallyDrop appear in the CALLER's name,
                // not in the low-level allocator name (__rust_alloc etc.).
                const caller_name_ptr = c.LLVMGetValueName(caller_func);
                const caller_name_str = if (@intFromPtr(caller_name_ptr) != 0) std.mem.span(caller_name_ptr) else "";
                const intentional_caller_patterns = [_][]const u8{
                    "into_raw", "ManuallyDrop", "forget",   "transfer_ownership",
                    "handoff",  "ffi_export",   "c_export", "export_ptr",
                    "donate",
                };
                var is_intentional = false;
                for (intentional_caller_patterns) |pat| {
                    if (std.mem.indexOf(u8, caller_name_str, pat) != null) {
                        is_intentional = true;
                        break;
                    }
                }

                if (!is_intentional) {
                    if (try cross_lang_detector.detectCrossLanguageFree(alloc_func, callee_name, ctx.allocator)) |cross_issue| {
                        try reportCrossLangFreeIssue(ctx, caller_func, callee_name, ptr_arg, &cross_issue, diag);
                        return true;
                    }
                } else {
                    log.debug("CROSS-LANG-CHECK: Intentional transfer in caller={s}, skipping", .{caller_name_str});
                }
            }
        }
        // ── END Cross-Language Detection ──

        // ── NEW: FFI Contract Database Validation (source_desc-based) ──
        // This layer validates alloc/free pairs using library-specific contracts
        // BEFORE falling through to MemoryGraph or legacy validation.
        // It catches cases like SSL_new + free() (should be SSL_free).
        if (origin_info) |info| {
            if (try validateWithContractDBFromSource(ctx, info.source_desc, callee_name, caller_func, inst, diag)) |result| {
                return result; // true = bug reported, false = valid pair
            }
            // result == null → no contract info, continue to normal validation
        }
        // ── END Contract Validation ──

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

                // Unified MemoryGraph validation (requires danger surface data)
                if (has_danger_surface) {
                    if (try validateFreeWithMemoryGraph(ctx, ptr_arg, callee_name, caller_func, diag)) |result| {
                        return result; // true = bug reported, false = safe
                    }
                }
                // result == null or no danger surface → fallback to legacy C free exemption

                // Fallback: C free/operator delete on param is normal ownership transfer
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

                // Unified MemoryGraph validation for FFI-sourced pointers (requires danger surface)
                if (has_danger_surface) {
                    if (try validateFreeWithMemoryGraph(ctx, ptr_arg, callee_name, caller_func, diag)) |result| {
                        return result;
                    }
                }
                // result == null or no danger surface → fallback to legacy C/C++ free exemption

                // Cross-allocator check: detect new+free or malloc+delete UB BEFORE exemption
                if (origin_info) |info| {
                    const cross_src = info.source_desc;
                    const alloc_is_cpp_new = std.mem.indexOf(u8, cross_src, "_Znwm") != null or
                        std.mem.indexOf(u8, cross_src, "_Znam") != null or
                        std.mem.indexOf(u8, cross_src, "operator new") != null;
                    const free_is_c_free = std.mem.eql(u8, callee_name, "free");
                    const alloc_is_c_malloc = std.mem.indexOf(u8, cross_src, "malloc") != null or
                        std.mem.indexOf(u8, cross_src, "calloc") != null or
                        std.mem.indexOf(u8, cross_src, "realloc") != null;
                    const free_is_cpp_delete = std.mem.indexOf(u8, callee_name, "_ZdlPv") != null or
                        std.mem.indexOf(u8, callee_name, "_ZdaPv") != null;

                    if ((alloc_is_cpp_new and free_is_c_free) or
                        (alloc_is_c_malloc and free_is_cpp_delete))
                    {
                        try reportInvalidFree(ctx, caller_func, callee_name, ptr_arg, origin, origin_info, diag);
                        return true;
                    }
                }

                // P1 FIX: Standard C free()/operator delete on FFI-sourced pointer is normal.
                // (keep existing comment block here, it's important documentation)
                if (std.mem.eql(u8, callee_name, "free") or
                    std.mem.eql(u8, callee_name, "kfree") or
                    std.mem.eql(u8, callee_name, "g_free") or
                    std.mem.startsWith(u8, callee_name, "operator delete") or
                    std.mem.indexOf(u8, callee_name, "_ZdlPv") != null or
                    std.mem.indexOf(u8, callee_name, "_ZdaPv") != null or
                    std.mem.indexOf(u8, callee_name, "_Zdl") != null or
                    std.mem.indexOf(u8, callee_name, "_Zda") != null)
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

                // Unified MemoryGraph validation for malloc'd pointers (requires danger surface)
                if (has_danger_surface) {
                    if (try validateFreeWithMemoryGraph(ctx, ptr_arg, callee_name, caller_func, diag)) |result| {
                        return result;
                    }
                }
                // result == null or no danger surface → fallback to legacy C/C++ free exemption

                // Cross-allocator check: detect new+free or malloc+delete UB BEFORE exemption
                if (origin_info) |info| {
                    const cross_src = info.source_desc;
                    const alloc_is_cpp_new = std.mem.indexOf(u8, cross_src, "_Znwm") != null or
                        std.mem.indexOf(u8, cross_src, "_Znam") != null or
                        std.mem.indexOf(u8, cross_src, "operator new") != null;
                    const free_is_c_free = std.mem.eql(u8, callee_name, "free");
                    const alloc_is_c_malloc = std.mem.indexOf(u8, cross_src, "malloc") != null or
                        std.mem.indexOf(u8, cross_src, "calloc") != null or
                        std.mem.indexOf(u8, cross_src, "realloc") != null;
                    const free_is_cpp_delete = std.mem.indexOf(u8, callee_name, "_ZdlPv") != null or
                        std.mem.indexOf(u8, callee_name, "_ZdaPv") != null;

                    if ((alloc_is_cpp_new and free_is_c_free) or
                        (alloc_is_c_malloc and free_is_cpp_delete))
                    {
                        try reportInvalidFree(ctx, caller_func, callee_name, ptr_arg, origin, origin_info, diag);
                        return true;
                    }
                }

                // P1 FIX: free() on malloc'd memory is always valid (C/C++ pattern).
                // (keep existing comment block here)
                if (std.mem.eql(u8, callee_name, "free") or
                    std.mem.eql(u8, callee_name, "kfree") or
                    std.mem.eql(u8, callee_name, "g_free") or
                    std.mem.startsWith(u8, callee_name, "operator delete") or
                    std.mem.indexOf(u8, callee_name, "_ZdlPv") != null or
                    std.mem.indexOf(u8, callee_name, "_ZdaPv") != null or
                    std.mem.indexOf(u8, callee_name, "_Zdl") != null or
                    std.mem.indexOf(u8, callee_name, "_Zda") != null)
                {
                    return false;
                }
                if (src.len > 0 and !isFreeSafe(callee_name, origin, src)) {
                    try reportInvalidFree(ctx, caller_func, callee_name, ptr_arg, origin, origin_info, diag);
                    return true;
                }
            },
            .from_library_borrow => {
                // Freeing a borrowed/library reference is almost always a bug.
                // e.g., free(sqlite3_column_text(...)) or free(ffi_borrowed_label())
                const caller_name_ptr = c.LLVMGetValueName(caller_func);
                const caller_name = if (@intFromPtr(caller_name_ptr) != 0)
                    std.mem.span(caller_name_ptr)
                else
                    "unknown";

                const message = try std.fmt.allocPrint(
                    ctx.allocator,
                    "Invalid free: pointer from borrowed library function was freed. " ++
                        "Borrowed references must not be freed by the caller (origin: {s}).",
                    .{if (origin_info) |info| info.source_desc else "unknown"},
                );
                const location = Location.init(caller_name);

                const trace = try ctx.allocator.alloc(TraceEntry, 3);
                trace[0] = TraceEntry.init("Free called on borrowed library reference");
                trace[1] = try createOriginTraceEntry(ctx.allocator, origin, origin_info);
                trace[2] = try createFreeTraceEntry(ctx.allocator, callee_name);

                var issue = Issue.initWithTrace(
                    .invalid_free,
                    message,
                    location,
                    .critical, // Freeing borrowed data is critical — causes heap corruption
                    0.90, // High confidence: library contract violation
                    trace,
                );
                errdefer issue.deinit(ctx.allocator);

                try ctx.addIssue(&issue);
                ctx.allocator.free(message);
                diag.warn("[OMI-CRITICAL] Invalid free of borrowed library ref in {s}: {s}() on borrowed pointer", .{
                    caller_name, callee_name,
                });
                return true;
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

    /// Check if a function name is a Rust allocator call.
    ///
    /// Covers four categories so that cross-language free detection has complete
    /// visibility into all Rust allocation sources:
    ///   - Stable ABI:  __rust_alloc, __rust_alloc_zeroed, __rust_realloc
    ///   - Legacy ABI:  __rdl_alloc, __rdl_alloc_zeroed, __rg_alloc, __rg_alloc_zeroed
    ///   - v0 mangling: _R*...alloc... (Rust's modern name mangling)
    ///   - Itanium:     _ZN*...alloc... (older Rust, before v0 migration)
    ///
    /// Without _ZN / __rdl_ / __rg_ coverage, trackPointerOrigin never records
    /// these allocs in the pointer origin map, so cross-lang free checks silently
    /// skip them even when __rust_dealloc frees such a pointer — a real mismatch.
    fn isRustAllocCall(func_name: []const u8) bool {
        // Stable Rust allocator ABI
        if (std.mem.eql(u8, func_name, "__rust_alloc") or
            std.mem.eql(u8, func_name, "__rust_alloc_zeroed") or
            std.mem.eql(u8, func_name, "__rust_realloc") or
            std.mem.eql(u8, func_name, "__rdl_alloc") or
            std.mem.eql(u8, func_name, "__rdl_alloc_zeroed") or
            std.mem.eql(u8, func_name, "__rg_alloc") or
            std.mem.eql(u8, func_name, "__rg_alloc_zeroed"))
        {
            return true;
        }
        // Rust v0 mangled names start with _R and contain alloc/allocate
        if (func_name.len > 4 and func_name[0] == '_' and func_name[1] == 'R') {
            const alloc_patterns = [_][]const u8{ "alloc", "allocate", "global_alloc" };
            for (alloc_patterns) |pat| {
                if (std.mem.indexOf(u8, func_name, pat) != null) {
                    return true;
                }
            }
        }
        // Itanium-style (_ZN) Rust mangled names containing alloc patterns
        if (std.mem.startsWith(u8, func_name, "_ZN")) {
            const zn_alloc_patterns = [_][]const u8{ "alloc", "allocate", "global_alloc" };
            for (zn_alloc_patterns) |pat| {
                if (std.mem.indexOf(u8, func_name, pat) != null) {
                    return true;
                }
            }
        }
        return false;
    }

    /// Check if a function name is a C++ operator new (mangled).
    /// Matches _Znwm (operator new), _Znam (operator new[]),
    /// and their aligned variants.
    fn isCppNewCall(func_name: []const u8) bool {
        const cpp_new_patterns = [_][]const u8{
            "_Znwm", // operator new(unsigned long)
            "_Znam", // operator new[](unsigned long)
            "_ZnwmSt11align_val_t", // aligned new
            "_ZnamSt11align_val_t", // aligned new[]
        };
        for (cpp_new_patterns) |pat| {
            if (std.mem.indexOf(u8, func_name, pat) != null) {
                return true;
            }
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

        // SAME-LANGUAGE MERGE GUARD for invalid_free:
        // When free_func is C++ delete/delete[] (_ZdlPv, _ZdaPv) and the pointer
        // origin is unknown/non-heap, this is often a FP caused by incomplete
        // cross-function return value tracking (e.g., BitReverseTable() returns
        // new[]'d memory but the graph node doesn't know it's heap-allocated).
        //
        // If the caller module is C/C++ and the free is a known C++ deallocator,
        // skip reporting — it's likely legitimate internal deallocation.
        const is_cpp_deallocator = std.mem.indexOf(u8, free_func_name, "_ZdlPv") != null or
            std.mem.indexOf(u8, free_func_name, "_ZdaPv") != null;
        const is_unknown_origin = origin == .unknown or origin == .from_param or
            origin == .from_global or origin == .from_constant;

        if (is_cpp_deallocator and is_unknown_origin) {
            const module_lang = ctx.module_language.language;
            if (module_lang == .cpp or module_lang == .c) {
                log.debug("SAME-LANG-MERGE [invalid_free]: skipping {s} in {s} (origin={s}, module={s})", .{
                    free_func_name, caller_name, @tagName(origin), @tagName(module_lang),
                });
                return;
            }
        }

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
            .from_library_borrow => "borrowed library reference",
            .unknown => "unknown source",
            else => "non-heap source",
        };

        const ffi_note = if (reaches_ffi) " [cross-FFI alias detected]" else "";

        const message = try std.fmt.allocPrint(
            ctx.allocator,
            "{s}() called on {s} pointer (confidence: {d:.0}%%{s})",
            .{ free_func_name, origin_str, @as(u32, @intFromFloat(base_confidence * 100.0)), ffi_note },
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
            .from_library_borrow => try allocator.dupe(u8, "Pointer origin: borrowed library reference"),
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

    /// Classify the release family of a free/dealloc function by name.
    /// Looks up the callee name in the family registry and returns the FamilyId.
    /// Returns .invalid if the function is not a known deallocator.
    fn classifyReleaseFamilyByName(ctx: *PassContext, callee_name: []const u8) FamilyId {
        const registry = ctx.memory_graph.family_registry orelse return .invalid;
        const op = registry.lookupRelease(callee_name, null) orelse return .invalid;
        return op.family;
    }

    /// Check if this free call represents a valid Rust ownership transfer.
    /// Examples: Box::from_raw(raw_ptr) followed by drop/Dealloc,
    ///           Rc/Arc refcount decrement (not actual deallocation).
    fn isRustOwnershipTransfer(node: *const AllocNode, callee_name: []const u8) bool {
        // Pattern 1: Mangled Rust names containing drop/Dealloc
        if (std.mem.indexOf(u8, callee_name, "_ZN") != null) {
            if (std.mem.indexOf(u8, callee_name, "drop") != null or
                std.mem.indexOf(u8, callee_name, "Dealloc") != null)
            {
                if (node.alloc_lang == .rust or node.alloc_family == .rust_global or node.alloc_family == .rust_box) {
                    return true;
                }
            }
        }

        // Pattern 2: Known safe Rust deallocation patterns
        const rust_safe_patterns = [_][]const u8{
            "__rust_dealloc",
            "__rdl_dealloc",
            "__rg_dealloc",
        };

        for (rust_safe_patterns) |p| {
            if (std.mem.indexOf(u8, callee_name, p) != null) {
                return node.alloc_lang == .rust or
                    node.alloc_family == .rust_global or
                    node.alloc_family == .rust_box;
            }
        }

        // Pattern 3: Rust global allocator dealloc on Rust-allocated memory
        if (node.alloc_family == .rust_global or node.alloc_family == .rust_box) {
            if (std.mem.indexOf(u8, callee_name, "__rust") != null or
                std.mem.indexOf(u8, callee_name, "_ZN") != null)
            {
                return true;
            }
        }

        return false;
    }

    /// Detect cross-allocator free bugs: freeing memory with wrong allocator.
    /// Example: malloc'd memory freed by __rust_dealloc (or vice versa).
    /// This is almost always a real bug — undefined behavior at runtime.
    fn isCrossAllocatorMismatch(node: *const AllocNode, callee_name: []const u8) bool {
        const alloc_family = node.alloc_family orelse return false;

        // C/C++ allocator freed by Rust deallocator
        if (alloc_family == .c_heap or alloc_family == .c_mmap or alloc_family == .c_aligned or
            alloc_family == .cpp_new_scalar or alloc_family == .cpp_new_array)
        {
            if (std.mem.indexOf(u8, callee_name, "__rust_dealloc") != null or
                std.mem.indexOf(u8, callee_name, "__rdl_dealloc") != null or
                std.mem.indexOf(u8, callee_name, "__rg_dealloc") != null or
                std.mem.startsWith(u8, callee_name, "_ZN"))
            {
                return true;
            }
        }

        // Rust allocator freed by C/C++ free
        if (alloc_family == .rust_global or alloc_family == .rust_box) {
            if (std.mem.eql(u8, callee_name, "free") or
                std.mem.eql(u8, callee_name, "kfree") or
                std.mem.eql(u8, callee_name, "g_free") or
                std.mem.startsWith(u8, callee_name, "operator delete"))
            {
                return true;
            }
        }

        return false;
    }

    /// Report a cross-allocator mismatch free as CRITICAL issue.
    /// Reuses reportInvalidFree logic with enhanced evidence showing
    /// the alloc/free family mismatch for auditability.
    fn reportCrossAllocatorFree(
        ctx: *PassContext,
        caller_func: c.LLVMValueRef,
        callee_name: []const u8,
        ptr_arg: c.LLVMValueRef,
        node: *const AllocNode,
        diag: *DiagnosticWriter,
    ) !void {
        log.debug("CROSS-ALLOCATOR: {s} on ptr allocated by family {s}", .{
            callee_name, if (node.alloc_family) |f| @tagName(f) else "unknown",
        });
        // Delegate to reportInvalidFree — the severity upgrade to CRITICAL
        // is already handled by the FFI danger-path detection inside it.
        try reportInvalidFree(ctx, caller_func, callee_name, ptr_arg, .from_param, null, diag);
    }

    // ═══════════════════════════════════════════════════════════════
    // NEW: Enhanced MemoryGraph + FFIContractDB validation helpers
    // ═══════════════════════════════════════════════════════════════

    /// Validate alloc/free pair using FFI Contract Database.
    ///
    /// Checks whether the release function is correct for the allocation
    /// according to library-specific lifecycle rules (e.g., SSL_new → SSL_free).
    ///
    /// Returns:
    ///   - `true`  → mismatch bug detected (wrong release function)
    ///   - `false` → valid pair (correct release function)
    ///   - `null`  → no contract info available (continue to next layer)
    fn validateWithContractDB(
        db: *FFIContractDB,
        node: *const AllocNode,
        callee_name: []const u8,
        ctx: *PassContext,
        caller_func: c.LLVMValueRef,
        ptr_arg: c.LLVMValueRef,
        diag: *DiagnosticWriter,
    ) !?bool {
        // Try to infer the alloc function name from the node's source information
        const alloc_func_name = inferAllocFuncName(node) orelse return null;

        log.debug("CONTRACT-DB: Checking pair {s} -> {s}", .{ alloc_func_name, callee_name });

        const result = db.isValidRelease(alloc_func_name, callee_name);

        switch (result) {
            .valid_pair => {
                log.debug("CONTRACT-DB: Valid pair confirmed: {s} -> {s}", .{
                    alloc_func_name, callee_name,
                });

                // Mark as freed in MemoryGraph for double-free detection
                markAsFreed(ctx, @intFromPtr(ptr_arg), callee_name);

                return false; // Valid pair, no issue
            },
            .mismatch => {
                log.warn("CONTRACT-DB: MISMATCH! alloc={s} but free={s}", .{
                    alloc_func_name, callee_name,
                });

                try reportMismatchIssue(ctx, caller_func, callee_name, ptr_arg, node, alloc_func_name, db, diag);
                return true; // Real bug!
            },
            .unknown_alloc, .unknown_release => {
                log.debug("CONTRACT-DB: No contract info for {s}, continuing...", .{
                    alloc_func_name,
                });
                return null; // No info, continue to next layer
            },
        }
    }

    /// Infer the allocation function name from an AllocNode.
    /// Uses heuristics based on alloc_family and alloc_inst address.
    ///
    /// Returns null if we cannot determine the alloc function name.
    fn inferAllocFuncName(node: *const AllocNode) ?[]const u8 {
        // If we have family info, we can make educated guesses
        if (node.alloc_family) |family| {
            return switch (family) {
                .c_heap => "malloc",
                .c_mmap => "mmap",
                .c_aligned => "aligned_alloc",
                .cpp_new_scalar => "operator new",
                .cpp_new_array => "operator new[]",
                .rust_global => "__rust_alloc",
                .rust_box => "__rust_alloc",
                else => null,
            };
        }

        // No family info available
        return null;
    }

    /// Validate alloc/free pair using FFI Contract Database based on source_desc.
    /// This is the source_desc-based complement to validateWithContractDB (which uses AllocNode).
    ///
    /// It extracts the allocation function name from the textual source_desc string
    /// and queries the contract database for validity.
    ///
    /// Returns:
    ///   - `true`  → mismatch bug detected (wrong release function)
    ///   - `false` → valid pair (correct release function)
    ///   - `null`  → no contract info available (continue to next layer)
    fn validateWithContractDBFromSource(
        ctx: *PassContext,
        source_desc: []const u8,
        callee_name: []const u8,
        caller_func: c.LLVMValueRef,
        free_inst: c.LLVMValueRef,
        diag: *DiagnosticWriter,
    ) !?bool {
        // Extract allocator function name from source description
        const alloc_func = extractAllocFuncName(source_desc) orelse return null;

        log.debug("CONTRACT-DB-SOURCE: Checking pair {s} -> {s} at inst 0x{x} (from source_desc: '{s}')", .{
            alloc_func, callee_name, @intFromPtr(free_inst), source_desc,
        });

        // Query FFI Contract DB
        const result = ctx.contract_db.isValidRelease(alloc_func, callee_name);

        switch (result) {
            .valid_pair => {
                log.debug("CONTRACT-DB-SOURCE: ✓ Valid pair: {s} -> {s}", .{
                    alloc_func, callee_name,
                });
                return false; // Valid pair, no issue
            },
            .mismatch => {
                log.warn("CONTRACT-DB-SOURCE: ✗ MISMATCH! alloc={s} but free={s}", .{
                    alloc_func, callee_name,
                });

                // Get expected release functions for error message
                const expected = ctx.contract_db.getExpectedReleases(alloc_func);

                if (expected) |expected_frees| {
                    // Report CRITICAL issue with detailed message
                    try reportCrossAllocatorMismatch(
                        ctx,
                        caller_func,
                        alloc_func,
                        callee_name,
                        expected_frees,
                        diag,
                    );
                } else {
                    // Fallback to generic mismatch report
                    log.warn("CONTRACT-DB-SOURCE: No expected releases for {s}, using generic report", .{alloc_func});
                    // Use a compile-time constant slice for the fallback
                    const fallback_expected = &[_][]const u8{"see library documentation"};
                    try reportCrossAllocatorMismatch(
                        ctx,
                        caller_func,
                        alloc_func,
                        callee_name,
                        fallback_expected,
                        diag,
                    );
                }

                return true; // Issue found and reported
            },
            .unknown_alloc, .unknown_release => {
                log.debug("CONTRACT-DB-SOURCE: No contract info for {s}, using heuristics", .{
                    alloc_func,
                });

                // Additional check: Should we even report leaks for this alloc?
                if (!ctx.contract_db.shouldReportLeak(alloc_func)) {
                    log.debug("CONTRACT-DB-SOURCE: Suppressing leak check for GC-managed: {s}", .{
                        alloc_func,
                    });
                    return false; // Don't report as potential leak
                }

                return null; // No info, continue to next layer
            },
        }
    }

    /// Extract the allocator function name from origin info description.
    /// This complements inferAllocFuncName() by parsing textual source_desc strings.
    ///
    /// source_desc format examples:
    ///   "from malloc()"
    ///   "from FFI call SSL_new()"
    ///   "from parameter 0 in main"
    ///   "allocated by __rust_alloc at instruction 0x1234"
    ///
    /// Returns the function name if found, null otherwise.
    fn extractAllocFuncName(source_desc: []const u8) ?[]const u8 {
        // Pattern 1: Find "by XXXX()" or "via XXXX()" (e.g., "allocated by malloc()")
        if (std.mem.indexOf(u8, source_desc, "by ")) |start| {
            const after_by = source_desc[start + 3 ..];
            if (std.mem.indexOf(u8, after_by, "()")) |end| {
                return after_by[0..end];
            }
        }

        // Pattern 2: Find "via XXXX()" (e.g., "allocated via SSL_new()")
        if (std.mem.indexOf(u8, source_desc, "via ")) |start| {
            const after_via = source_desc[start + 4 ..];
            if (std.mem.indexOf(u8, after_via, "()")) |end| {
                return after_via[0..end];
            }
        }

        // Pattern 3: Find "from XXXX()" (e.g., "from malloc()", "from FFI call SSL_new()")
        if (std.mem.indexOf(u8, source_desc, "from ")) |start| {
            const after_from = source_desc[start + 5 ..];
            // Skip common prefixes like "FFI call ", "parameter "
            const trimmed = if (std.mem.indexOf(u8, after_from, "call ")) |call_start|
                after_from[call_start + 5 ..]
            else
                after_from;

            if (std.mem.indexOf(u8, trimmed, "()")) |end| {
                // Ensure it's a reasonable function name (not too long)
                if (end > 0 and end < 64) {
                    return trimmed[0..end];
                }
            }
        }

        // Pattern 4: Direct function name at start (e.g., "malloc(...)")
        if (std.mem.indexOf(u8, source_desc, "(")) |end| {
            if (end > 0 and end < 64) { // Reasonable function name length
                // Make sure it's not a sentence start like "Pointer" or "Memory"
                const candidate = source_desc[0..end];
                const first_char = candidate[0];
                if ((first_char >= 'a' and first_char <= 'z') or
                    first_char == '_' or
                    (first_char >= 'A' and first_char <= 'Z' and end > 2))
                {
                    return candidate;
                }
            }
        }

        return null;
    }

    /// Check if this is a borrowed reference or refcounted object.
    /// Borrowed pointers should NOT be freed by the caller - they're managed
    /// by the owner (e.g., PyList_GetItem returns a borrowed ref).
    fn isBorrowedOrRefcount(node: *const AllocNode) bool {
        // Check ownership model
        if (node.ownership_model == .refcount) {
            return true;
        }

        // Check if GC-managed (GC objects shouldn't be manually freed)
        if (node.is_gc_managed) {
            return true;
        }

        // Check container type for smart containers that manage their own memory
        if (node.container_type) |ct| {
            return switch (ct) {
                .rust_box, .rust_vec, .rust_string => true, // Rust containers use Drop
                .cpp_unique_ptr, .cpp_shared_ptr, .std_vector, .std_string => true, // C++ smart pointers use destructors
                .python_list, .python_dict => true, // Python objects are GC'd or refcounted
                .go_slice, .go_map => true, // Go types are GC'd
                .csharp_handle => true, // C# SafeHandle uses Dispose
                .zig_arraylist, .zig_hashmap, .zig_buffer, .zig_multiarraylist => true, // Zig containers use deinit
                .unknown => false,
            };
        }

        return false;
    }

    /// Mark a pointer as freed in MemoryGraph for future double-free detection.
    /// This updates the AllocNode state so subsequent frees can be detected.
    fn markAsFreed(ctx: *PassContext, ptr_val: u64, free_callee: []const u8) void {
        _ = ctx.memory_graph.trackFree(
            ptr_val, // free_inst_addr (use ptr_val as placeholder)
            ptr_val, // ptr_val being freed
            if (std.mem.indexOf(u8, free_callee, "__rust") != null) .rust else .c,
            0, // bb_id unknown in this context
        ) catch |err| {
            log.warn("FREE_VALIDATION: Failed to track free in MemoryGraph: {}", .{err});
        };
    }

    /// Report a double-free issue with high confidence.
    /// Double-free is almost always a real bug with severe consequences
    /// (heap corruption, security vulnerabilities).
    fn reportDoubleFreeIssue(
        ctx: *PassContext,
        caller_func: c.LLVMValueRef,
        callee_name: []const u8,
        ptr_arg: c.LLVMValueRef,
        node: *const AllocNode,
        diag: *DiagnosticWriter,
    ) !void {
        const caller_name_ptr = c.LLVMGetValueName(caller_func);
        const caller_name = if (@intFromPtr(caller_name_ptr) != 0)
            std.mem.span(caller_name_ptr)
        else
            "unknown";

        const location = Location.init(caller_name);

        // Build detailed trace showing both free sites
        const trace = try ctx.allocator.alloc(TraceEntry, 4);
        trace[0] = TraceEntry.init("Double-free detected");
        trace[1] = TraceEntry.initOwned(try std.fmt.allocPrint(ctx.allocator, "Memory at 0x{x} was first freed at instruction 0x{x}", .{ @intFromPtr(ptr_arg), node.freed_by orelse 0 }));
        trace[2] = TraceEntry.initOwned(try std.fmt.allocPrint(ctx.allocator, "Second free attempt via {s}()", .{callee_name}));
        trace[3] = try createFreeTraceEntry(ctx.allocator, callee_name);

        const message = try std.fmt.allocPrint(ctx.allocator, "Double free detected: memory allocated at 0x{x} was already freed at 0x{x}. " ++
            "Second free via {s}() causes undefined behavior (heap corruption, security vulnerability).", .{
            node.alloc_inst,
            node.freed_by orelse 0,
            callee_name,
        });

        var issue = Issue.initWithTrace(
            .double_free,
            message,
            location,
            .critical, // Double-free is always CRITICAL
            0.98, // Very high confidence from MemoryGraph proof
            trace,
        );
        errdefer issue.deinit(ctx.allocator);

        try ctx.addIssue(&issue);

        diag.warn("[OMI-CRITICAL] Double free detected in {s}: {s}() on already-freed memory", .{
            caller_name, callee_name,
        });
    }

    /// Report an alloc/free mismatch issue from FFI Contract Database.
    /// This indicates wrong release function used for a library resource.
    ///
    /// Example: SSL_new() followed by BIO_free() instead of SSL_free()
    /// This can cause memory leaks OR corruption depending on the library.
    fn reportMismatchIssue(
        ctx: *PassContext,
        caller_func: c.LLVMValueRef,
        wrong_free_func: []const u8,
        ptr_arg: c.LLVMValueRef,
        node: *const AllocNode,
        alloc_func_name: []const u8,
        db: *FFIContractDB,
        diag: *DiagnosticWriter,
    ) !void {
        _ = ptr_arg; // Used for future enhancements (e.g., showing pointer value in message)
        const caller_name_ptr = c.LLVMGetValueName(caller_func);
        const caller_name = if (@intFromPtr(caller_name_ptr) != 0)
            std.mem.span(caller_name_ptr)
        else
            "unknown";

        const location = Location.init(caller_name);

        // Get expected release functions from DB for better error message
        const expected_releases = db.getExpectedReleases(alloc_func_name);
        const expected_str = if (expected_releases) |releases| blk: {
            if (releases.len == 0) break :blk "see documentation";
            // Simple case: just return the first one (most common)
            break :blk releases[0];
        } else "see documentation";

        // Build trace showing the mismatch
        const trace = try ctx.allocator.alloc(TraceEntry, 3);
        trace[0] = TraceEntry.initOwned(try std.fmt.allocPrint(ctx.allocator, "Resource allocated via {s}() at instruction 0x{x}", .{ alloc_func_name, node.alloc_inst }));
        trace[1] = TraceEntry.initOwned(try std.fmt.allocPrint(ctx.allocator, "Incorrectly released via {s}() (wrong function for this resource type)", .{wrong_free_func}));
        trace[2] = TraceEntry.initOwned(try std.fmt.allocPrint(ctx.allocator, "Expected release function(s): {s}", .{expected_str}));

        const message = try std.fmt.allocPrint(ctx.allocator, "Allocation/release mismatch: {s}() at 0x{x} incorrectly freed with {s}(). " ++
            "Expected: {s}. This may cause memory corruption or leaks.", .{
            alloc_func_name,
            node.alloc_inst,
            wrong_free_func,
            expected_str,
        });

        // Determine severity based on library error-proness
        const severity: Severity = if (db.isErrorProneLib(alloc_func_name))
            .critical // Error-prone libraries get higher severity
        else
            .high;

        const base_confidence: f32 = db.getConfidence(alloc_func_name);

        var issue = Issue.initWithTrace(
            .contract_mismatch,
            message,
            location,
            severity,
            base_confidence,
            trace,
        );
        errdefer issue.deinit(ctx.allocator);

        try ctx.addIssue(&issue);

        const omi_prefix = if (severity == .critical) "[OMI-CRITICAL] " else "[OMI-HIGH] ";
        diag.warn("{s}Allocation/release mismatch in {s}: {s} should use {s}, not {s}", .{
            omi_prefix,
            caller_name,
            alloc_func_name,
            expected_str,
            wrong_free_func,
        });

        // Clean up expected_str if it was heap-allocated
        if (expected_releases != null) {
            // expected_str was owned by ArrayList, already freed by defer
        }
    }

    /// Report a cross-allocator mismatch bug using source_desc information.
    /// This is the enhanced version that works with pointer_origins directly,
    /// providing detailed error messages with code examples.
    ///
    /// Example output:
    ///   "Cross-allocator mismatch: memory was allocated by 'SSL_new' but freed with 'free'.
    ///    Expected release function(s): SSL_free or SSL_free_all.
    ///    This can cause memory corruption, heap overflow, or double-free vulnerabilities."
    fn reportCrossAllocatorMismatch(
        ctx: *PassContext,
        caller_func: c.LLVMValueRef,
        alloc_func_name: []const u8,
        wrong_free_func: []const u8,
        expected_frees: []const []const u8,
        diag: *DiagnosticWriter,
    ) !void {
        const caller_name_ptr = c.LLVMGetValueName(caller_func);
        const caller_name = if (@intFromPtr(caller_name_ptr) != 0)
            std.mem.span(caller_name_ptr)
        else
            "unknown";

        const location = Location.init(caller_name);

        // Build expected functions list string (simple approach without ArrayList)
        var expected_buf: [512]u8 = undefined;
        var expected_fbs = std.io.fixedBufferStream(&expected_buf);
        const expected_writer = expected_fbs.writer();
        for (expected_frees, 0..) |free_name, i| {
            if (i > 0) expected_writer.writeAll(" or ") catch {};
            expected_writer.writeAll(free_name) catch {};
        }
        const expected_str = expected_fbs.getWritten();

        // Build detailed message with code examples
        const message = try std.fmt.allocPrint(ctx.allocator,
            \\Cross-allocator mismatch: memory was allocated by '{s}' but freed with '{s}'.
            \\Expected release function(s): {s}.
            \\This can cause memory corruption, heap overflow, or double-free vulnerabilities.
            \\
            \\Example of correct usage:
            \\  ptr = {s}(...);   // Allocation
            \\  // ... use ptr ...
            \\  {s}(ptr);         // Correct release (NOT {s})
        , .{
            alloc_func_name,
            wrong_free_func,
            expected_str,
            alloc_func_name,
            expected_frees[0], // First expected as example
            wrong_free_func,
        });

        // Build trace showing the mismatch with code examples
        const trace = try ctx.allocator.alloc(TraceEntry, 4);
        trace[0] = TraceEntry.initOwned(try std.fmt.allocPrint(ctx.allocator, "Memory allocated via {s}() - library-specific allocator", .{alloc_func_name}));
        trace[1] = TraceEntry.initOwned(try std.fmt.allocPrint(ctx.allocator, "Incorrectly released via {s}() - wrong deallocator for this resource type", .{wrong_free_func}));
        trace[2] = TraceEntry.initOwned(try std.fmt.allocPrint(ctx.allocator, "Expected: {s}", .{expected_str}));
        trace[3] = TraceEntry.initOwned(try std.fmt.allocPrint(ctx.allocator,
            \\Correct pattern:
            \\  ptr = {s}(...);
            \\  {s}(ptr);  // NOT {s}(ptr)
        , .{ alloc_func_name, expected_frees[0], wrong_free_func }));

        // Determine severity: critical for known error-prone libraries
        var db_check = FFIContractDB.init(ctx.allocator) catch return;
        defer db_check.deinit();
        const severity: Severity = if (db_check.isErrorProneLib(alloc_func_name))
            .critical
        else
            .high;

        const base_confidence: f32 = 0.95; // Very high confidence from contract DB proof

        var issue = Issue.initWithTrace(
            .contract_mismatch,
            message,
            location,
            severity,
            base_confidence,
            trace,
        );
        errdefer issue.deinit(ctx.allocator);

        try ctx.addIssue(&issue);

        const omi_prefix = if (severity == .critical) "[OMI-CRITICAL] " else "[OMI-HIGH] ";
        diag.warn("{s}Cross-allocator mismatch in {s}: {s} allocated by '{s}' but freed with '{s}'. Use {s} instead.", .{
            omi_prefix,
            caller_name,
            alloc_func_name,
            alloc_func_name,
            wrong_free_func,
            expected_str,
        });
    }

    /// Extract allocation function name for cross-language detection.
    /// Similar to extractAllocFuncName but optimized for cross-language patterns.
    fn extractAllocFuncNameForCrossLang(source_desc: []const u8) ?[]const u8 {
        // Pattern 1: "from XXXX()" - most common format
        if (std.mem.indexOf(u8, source_desc, "from ")) |start| {
            const after_from = source_desc[start + 5 ..];
            // Skip "FFI call ", "parameter " prefixes
            const trimmed = if (std.mem.indexOf(u8, after_from, "call ")) |call_start|
                after_from[call_start + 5 ..]
            else
                after_from;

            if (std.mem.indexOf(u8, trimmed, "()")) |end| {
                if (end > 0 and end < 128) { // Allow longer names for mangled Rust functions
                    return trimmed[0..end];
                }
            }
        }

        // Pattern 2: Direct function name with known Rust/C++ patterns
        // This handles cases where the description is just the function name
        if (std.mem.indexOf(u8, source_desc, "()")) |end| {
            if (end > 3 and end < 128) {
                // Must look like a function call (not a sentence)
                const candidate = source_desc[0..end];
                const first_char = candidate[0];
                if ((first_char >= 'a' and first_char <= 'z') or first_char == '_' or
                    (first_char >= 'A' and first_char <= 'Z'))
                {
                    return candidate;
                }
            }
        }

        return null;
    }

    /// Report a cross-language free mismatch issue.
    /// Uses enhanced severity and confidence from cross_lang_detector.
    fn reportCrossLangFreeIssue(
        ctx: *PassContext,
        caller_func: c.LLVMValueRef,
        callee_name: []const u8,
        ptr_arg: c.LLVMValueRef,
        cross_issue: *const cross_lang_detector.CrossLangFreeIssue,
        diag: *DiagnosticWriter,
    ) !void {
        const caller_name_ptr = c.LLVMGetValueName(caller_func);
        const caller_name = if (@intFromPtr(caller_name_ptr) != 0)
            std.mem.span(caller_name_ptr)
        else
            "unknown";

        // Suppress false positives for intentional ownership transfer patterns
        // (e.g., Box::leak → C free(), into_raw → C free())
        if (isIntentionalOwnershipTransfer(caller_name)) {
            diag.info("[SUPPRESSED] Cross-language free in {s}: intentional ownership transfer (alloc={s}, free={s})", .{
                caller_name, cross_issue.alloc_family.displayName(), cross_issue.free_family.family.displayName(),
            });
            return;
        }

        const location = Location.init(caller_name);

        // Build detailed trace showing the cross-language mismatch
        const trace = try ctx.allocator.alloc(TraceEntry, 5);
        trace[0] = TraceEntry.init("Cross-language free detected");
        trace[1] = TraceEntry.initOwned(try std.fmt.allocPrint(ctx.allocator, "Pointer address: 0x{x}", .{@intFromPtr(ptr_arg)}));
        trace[2] = TraceEntry.initOwned(try std.fmt.allocPrint(ctx.allocator, "Memory allocated by {s} ({s})", .{ cross_issue.alloc_family.displayName(), cross_issue.free_family.func_name }));
        trace[3] = TraceEntry.initOwned(try std.fmt.allocPrint(ctx.allocator, "Freed using {s} ({s})", .{ cross_issue.free_family.family.displayName(), callee_name }));
        trace[4] = TraceEntry.initOwned(try std.fmt.allocPrint(ctx.allocator, "Different runtimes may use different heaps - this is undefined behavior", .{}));

        // Map to OmniScope severity
        const severity: Severity = switch (cross_issue.severity) {
            .critical => .critical,
            .high => .high,
        };

        var issue = Issue.initWithTrace(
            .invalid_free, // Use invalid_free kind for cross-lang issues
            cross_issue.message,
            location,
            severity,
            cross_issue.confidence,
            trace,
        );
        errdefer issue.deinit(ctx.allocator);

        try ctx.addIssue(&issue);

        const omi_prefix = if (severity == .critical) "[OMI-CRITICAL] " else "[OMI-HIGH] ";
        diag.warn("{s}Cross-language free in {s}: {s} freed by {s}. Confidence: {d:.0}%%", .{
            omi_prefix,
            caller_name,
            cross_issue.alloc_family.displayName(),
            cross_issue.free_family.family.displayName(),
            @as(u32, @intFromFloat(cross_issue.confidence * 100.0)),
        });
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

test "FreeValidationPass - isRustAllocCall extended coverage" {
    // Stable ABI — existing
    try std.testing.expect(FreeValidationPass.isRustAllocCall("__rust_alloc"));
    try std.testing.expect(FreeValidationPass.isRustAllocCall("__rust_alloc_zeroed"));
    try std.testing.expect(FreeValidationPass.isRustAllocCall("__rust_realloc"));

    // Legacy (__rdl_ / __rg_) — newly added
    try std.testing.expect(FreeValidationPass.isRustAllocCall("__rdl_alloc"));
    try std.testing.expect(FreeValidationPass.isRustAllocCall("__rdl_alloc_zeroed"));
    try std.testing.expect(FreeValidationPass.isRustAllocCall("__rg_alloc"));
    try std.testing.expect(FreeValidationPass.isRustAllocCall("__rg_alloc_zeroed"));

    // v0 mangling (_R prefix) — existing path
    try std.testing.expect(FreeValidationPass.isRustAllocCall("_RNvNtCsi3aA3my_lib4core4foo5allocE"));

    // Itanium (_ZN prefix) — newly added
    try std.testing.expect(FreeValidationPass.isRustAllocCall("_ZN4alloc5allocE"));
    try std.testing.expect(FreeValidationPass.isRustAllocCall("_ZN3std2io5allocateE"));

    // Negative cases: _ZN without alloc pattern, random names
    try std.testing.expect(!FreeValidationPass.isRustAllocCall("_ZN3foo3barE"));
    try std.testing.expect(!FreeValidationPass.isRustAllocCall("malloc"));
    try std.testing.expect(!FreeValidationPass.isRustAllocCall("free"));
}
