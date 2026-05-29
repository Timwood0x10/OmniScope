//! Semantic Resolver Pass
//!
//! This pass implements the semantic resolution layer that processes
//! LLVM IR and applies language-specific patterns to resolve ownership
//! and safety semantics before heavy analysis passes.

const std = @import("std");
const log = @import("../../common/log.zig");
const PassContext = @import("../pass.zig").PassContext;
const DiagnosticWriter = @import("../pass.zig").DiagnosticWriter;
const llvm_safe = @import("../../ir/llvm_safe.zig");

const resolution_engine = @import("../../semantics/resolution_engine.zig");
const ResolutionEngine = resolution_engine.ResolutionEngine;
const semantic_patterns = @import("../../semantics/semantic_patterns.zig");

const c = @import("../../ir/llvm_raw.zig").c;

// Nomicon detectors
const nomicon_ch04 = @import("../../semantics/nomicon/ch04_conversions.zig");
const nomicon_ch05 = @import("../../semantics/nomicon/ch05_uninitialized.zig");
const nomicon_ch06 = @import("../../semantics/nomicon/ch06_obrm.zig");
const nomicon_ch08 = @import("../../semantics/nomicon/ch08_concurrency.zig");
const nomicon_ch09 = @import("../../semantics/nomicon/ch09_vec_box.zig");
const nomicon_ch10 = @import("../../semantics/nomicon/ch10_pin_box.zig");
const nomicon_posix = @import("../../semantics/nomicon/posix_syscalls.zig");

// R-0~R-7 pattern detectors (new patterns/ directory)
const patterns_param_attr = @import("../../semantics/patterns/param_attr.zig");
const patterns_heap_provenance = @import("../../semantics/patterns/heap_provenance.zig");
const patterns_into_raw = @import("../../semantics/patterns/into_raw_transfer.zig");
const patterns_library_alloc = @import("../../semantics/patterns/library_alloc_pairs.zig");
const patterns_lang_detector = @import("../../semantics/patterns/lang_detector.zig");
const patterns_interior_mut = @import("../../semantics/patterns/interior_mut.zig");

/// Semantic resolver pass
pub const SemanticResolverPass = struct {
    pub const name = "SemanticResolver";
    pub const kind = @import("../pass.zig").PassKind.analysis;
    pub const deps = &[_][]const u8{};

    /// Run the semantic resolver pass
    pub fn run(ctx: *PassContext, diag: *DiagnosticWriter) !void {
        log.debug("[SemanticResolver] Starting semantic resolution...", .{});

        const start_time = std.time.nanoTimestamp();

        // Initialize resolution engine
        var engine = try ResolutionEngine.init(ctx.allocator);
        errdefer engine.deinit();

        // Register built-in patterns for common languages
        try registerBuiltinPatterns(&engine);

        // Process the module
        if (ctx.module) |mod| {
            const raw_mod = mod.raw;
            var func = c.LLVMGetFirstFunction(raw_mod);
            while (@intFromPtr(func) != 0) : (func = c.LLVMGetNextFunction(func)) {
                if (c.LLVMIsDeclaration(func) != 0) continue;

                // Get the caller function name for tagging
                const caller_name_raw = c.LLVMGetValueName(func);
                const caller_name = if (caller_name_raw != null) std.mem.span(caller_name_raw) else "unknown";

                // Process all basic blocks and instructions
                var bb = c.LLVMGetFirstBasicBlock(func);
                while (@intFromPtr(bb) != 0) : (bb = c.LLVMGetNextBasicBlock(bb)) {
                    var inst = c.LLVMGetFirstInstruction(bb);
                    while (@intFromPtr(inst) != 0) : (inst = c.LLVMGetNextInstruction(inst)) {
                        // Process call instructions
                        const opcode = c.LLVMGetInstructionOpcode(inst);
                        if (llvm_safe.isCallOrInvoke(opcode)) {
                            const called_val = c.LLVMGetCalledValue(inst);
                            if (@intFromPtr(called_val) != 0) {
                                const called_name_ptr = c.LLVMGetValueName(called_val);
                                if (@intFromPtr(called_name_ptr) != 0) {
                                    const callee_name = std.mem.span(called_name_ptr);
                                    const inst_addr = @as(u64, @intFromPtr(inst));

                                    // Process the call with the resolution engine
                                    // Pass both caller and callee names so the engine
                                    // can tag the caller with the callee's semantic kind
                                    try engine.processFunctionCall(
                                        callee_name,
                                        caller_name,
                                        inst_addr,
                                        "unknown",
                                        0,
                                    );
                                }
                            }
                        }
                    }
                }
            }
        }

        // Run Nomicon detectors to populate SRT with semantic resolutions
        if (ctx.module) |mod| {
            const raw_mod = mod.raw;
            const srt = engine.getSemanticTree();

            log.debug("[SemanticResolver] Running Nomicon detectors...", .{});

            // Ch4: Type Conversions & Transmute (bitcast size mismatch, inttoptr)
            nomicon_ch04.detect(raw_mod, srt, diag) catch |err| {
                log.warn("[SemanticResolver] ch04_conversions detector failed: {any}", .{err});
            };

            // Ch5: Uninitialized Memory (MaybeUninit::assume_init)
            nomicon_ch05.detect(raw_mod, srt, diag) catch |err| {
                log.warn("[SemanticResolver] ch05_uninitialized detector failed: {any}", .{err});
            };

            // Ch6: OBRM (Drop / drop_in_place / tail dealloc)
            nomicon_ch06.detect(raw_mod, srt, diag) catch |err| {
                log.warn("[SemanticResolver] ch06_obrm detector failed: {any}", .{err});
            };

            // Ch8: Concurrency Violations (Send/Sync trait abuse)
            nomicon_ch08.detect(raw_mod, srt, diag) catch |err| {
                log.warn("[SemanticResolver] ch08_concurrency detector failed: {any}", .{err});
            };

            // Ch9: Vec/Box heap ownership
            nomicon_ch09.detect(raw_mod, srt, diag) catch |err| {
                log.warn("[SemanticResolver] ch09_vec_box detector failed: {any}", .{err});
            };

            // Ch10: Pin/ManuallyDrop/OnceLock + UnsafeCell chain
            nomicon_ch10.detect(raw_mod, srt, diag) catch |err| {
                log.warn("[SemanticResolver] ch10_pin_box detector failed: {any}", .{err});
            };

            // POSIX syscall classification
            nomicon_posix.detect(raw_mod, srt, diag) catch |err| {
                log.warn("[SemanticResolver] posix_syscalls detector failed: {any}", .{err});
            };

            // ── R-0: LLVM parameter attributes (readonly/noalias → 1877 FP main cause) ──
            patterns_param_attr.detect(raw_mod, srt, diag) catch |err| {
                log.warn("[SemanticResolver] param_attr detector failed: {any}", .{err});
            };

            // ── R-1: Heap provenance (SROA + DI → borrow_escape 71 FP) ──
            patterns_heap_provenance.detect(raw_mod, srt, diag) catch |err| {
                log.warn("[SemanticResolver] heap_provenance detector failed: {any}", .{err});
            };

            // ── R-2: Interior mutability (UnsafeCell DI chain → write_to_immutable FP) ──
            patterns_interior_mut.detect(raw_mod, srt, diag) catch |err| {
                log.warn("[SemanticResolver] interior_mut detector failed: {any}", .{err});
            };

            // ── R-6: into_raw ownership transfer (Box/CString::into_raw → cross_lang_free 4 FP) ──
            patterns_into_raw.detect(raw_mod, srt, diag) catch |err| {
                log.warn("[SemanticResolver] into_raw_transfer detector failed: {any}", .{err});
            };

            // ── R-7: Library allocator pairs (mimalloc/zlib/openssl/sqlite/cgo/JNI/Python/Zig) ──
            patterns_library_alloc.detect(raw_mod, srt, diag) catch |err| {
                log.warn("[SemanticResolver] library_alloc_pairs detector failed: {any}", .{err});
            };

            // ── R-5: Language detection (query-only, no SRT writes) ──
            patterns_lang_detector.detect(raw_mod, srt, diag) catch |err| {
                log.warn("[SemanticResolver] lang_detector failed: {any}", .{err});
            };
        }

        const end_time = std.time.nanoTimestamp();
        const duration_ms = @as(f64, @floatFromInt(end_time - start_time)) / 1_000_000.0;

        // Log statistics
        const stats = engine.getStats();
        log.debug(
            "[SemanticResolver] Completed in {d:.1}ms: total_nodes={d}, resolutions={d}, patterns_applied={d}, allocs={d}, frees={d}, caller_semantics={d}",
            .{ duration_ms, stats.total_nodes, stats.resolutions_made, stats.patterns_applied, stats.allocations_tracked, stats.frees_tracked, engine.caller_semantics.count() },
        );

        // Store the resolution engine in context for later passes
        const engine_ptr = try ctx.allocator.create(ResolutionEngine);
        engine_ptr.* = engine;
        ctx.semantic_resolution = engine_ptr;

        // Note: We don't deinit the engine here since it's now owned by PassContext
    }

    /// Register built-in patterns for common allocation/release functions.
    ///
    /// Design principle: match NAMING CONVENTIONS (language runtime standards),
    /// not project-specific function names. All patterns here are:
    ///   - Official language runtime symbols (e.g., __rust_alloc, _cgo_allocate)
    ///   - Standard library functions (e.g., malloc, objc_alloc)
    ///   - FFI bridge conventions with well-documented prefixes
    fn registerBuiltinPatterns(engine: *ResolutionEngine) !void {
        // ── C standard library ──
        _ = try engine.registerPattern(
            "malloc_alloc",
            "C malloc allocation",
            semantic_patterns.PatternType.allocation,
            &[_][]const u8{ "malloc", "calloc", "realloc", "aligned_alloc" },
            100,
            "c",
        );
        _ = try engine.registerPattern(
            "free_release",
            "C free release",
            semantic_patterns.PatternType.release,
            &[_][]const u8{"free"},
            100,
            "c",
        );

        // ── Rust standard library ──
        _ = try engine.registerPattern(
            "rust_alloc",
            "Rust global allocator allocation",
            semantic_patterns.PatternType.allocation,
            &[_][]const u8{ "__rust_alloc", "__rust_alloc_zeroed" },
            100,
            "rust",
        );
        _ = try engine.registerPattern(
            "rust_dealloc",
            "Rust global allocator release",
            semantic_patterns.PatternType.release,
            &[_][]const u8{"__rust_dealloc"},
            100,
            "rust",
        );
        _ = try engine.registerPattern(
            "rust_drop",
            "Rust Drop trait / compiler drop glue",
            semantic_patterns.PatternType.release,
            &[_][]const u8{ "drop_in_place", "__rust_drop_in_place" },
            90,
            "rust",
        );

        // ── C++ standard library (Itanium mangled) ──
        _ = try engine.registerPattern(
            "cpp_new",
            "C++ new operator allocation",
            semantic_patterns.PatternType.allocation,
            &[_][]const u8{ "_Znwm", "_Znam", "_ZnwmSt11align_val_t" },
            100,
            "cpp",
        );
        _ = try engine.registerPattern(
            "cpp_delete",
            "C++ delete operator release",
            semantic_patterns.PatternType.release,
            &[_][]const u8{ "_ZdlPv", "_ZdaPv", "_ZdlPvm" },
            100,
            "cpp",
        );

        // ── Go/cgo runtime (official cgo naming convention) ──
        // cgo-generated wrappers follow strict naming:
        //   _cgo_*       — C-side cgo runtime helpers
        //   _Cfunc_*     — Go→C call wrappers (Go functions called from C)
        //   _Cgo_*       — C→Go call wrappers (C functions called from Go)
        _ = try engine.registerPattern(
            "cgo_alloc",
            "Go cgo runtime allocation (_cgo_allocate)",
            semantic_patterns.PatternType.allocation,
            &[_][]const u8{ "_cgo_allocate", "_cgo_allocate_local" },
            95,
            "go",
        );
        _ = try engine.registerPattern(
            "cgo_free",
            "Go cgo runtime release (_cgo_free)",
            semantic_patterns.PatternType.release,
            &[_][]const u8{"_cgo_free"},
            95,
            "go",
        );
        _ = try engine.registerPattern(
            "cgo_gomalloc",
            "Go heap allocation via cgo (_Cfunc_GoMalloc)",
            semantic_patterns.PatternType.allocation,
            &[_][]const u8{ "_Cfunc_GoMalloc", "_Cfunc_GoAlloc" },
            90,
            "go",
        );
        _ = try engine.registerPattern(
            "cgo_gofree",
            "Go heap release via cgo (_Cfunc_GoFree)",
            semantic_patterns.PatternType.release,
            &[_][]const u8{"_Cfunc_GoFree"},
            90,
            "go",
        );

        // ── Objective-C runtime ──
        _ = try engine.registerPattern(
            "objc_alloc",
            "Objective-C object allocation",
            semantic_patterns.PatternType.allocation,
            &[_][]const u8{
                "objc_alloc",         "objc_allocInit",
                "objc_allocWithZone", "class_createInstance",
                "NSAllocateObject",   "+[NSObject alloc]",
                "malloc_zone_malloc", "malloc_zone_calloc",
            },
            90,
            "objc",
        );
        _ = try engine.registerPattern(
            "objc_free",
            "Objective-C object release",
            semantic_patterns.PatternType.release,
            &[_][]const u8{
                "objc_release",       "objc_autorelease",
                "CFRelease",          "CGImageRelease",
                "NSDeallocateObject", "free",
            },
            90,
            "objc",
        );

        // ── Python/C API ──
        _ = try engine.registerPattern(
            "py_alloc",
            "Python C API allocation",
            semantic_patterns.PatternType.allocation,
            &[_][]const u8{
                "PyMem_Malloc",         "PyMem_Calloc",       "PyMem_Realloc",
                "PyObject_Malloc",      "PyObject_New",       "PyObject_NewVar",
                "PyList_New",           "PyDict_New",         "PyTuple_New",
                "PyUnicode_FromString", "PyBytes_FromString",
            },
            85,
            "python",
        );
        _ = try engine.registerPattern(
            "py_free",
            "Python C API release",
            semantic_patterns.PatternType.release,
            &[_][]const u8{
                "PyMem_Free", "PyObject_Free",
                "Py_DECREF",  "Py_XDECREF",
                "Py_CLEAR",
            },
            85,
            "python",
        );

        // ── JNI/Java Native Interface ──
        _ = try engine.registerPattern(
            "jni_alloc",
            "JNI local reference allocation",
            semantic_patterns.PatternType.allocation,
            &[_][]const u8{
                "NewGlobalRef",     "NewLocalRef",
                "FindClass",        "GetObjectClass",
                "NewStringUTF",     "NewByteArray",
                "CallObjectMethod", "CallStaticObjectMethod",
            },
            80,
            "java",
        );
        _ = try engine.registerPattern(
            "jni_free",
            "JNI reference release",
            semantic_patterns.PatternType.release,
            &[_][]const u8{
                "DeleteLocalRef", "DeleteGlobalRef",
            },
            80,
            "java",
        );

        // ── Node.js/N-API ──
        _ = try engine.registerPattern(
            "napi_alloc",
            "Node.js N-API value creation",
            semantic_patterns.PatternType.allocation,
            &[_][]const u8{
                "napi_create_object",      "napi_create_array",
                "napi_create_string_utf8", "napi_create_external_arraybuffer",
                "napi_get_cb_info",
            },
            80,
            "nodejs",
        );
        _ = try engine.registerPattern(
            "napi_free",
            "Node.js N-API reference release",
            semantic_patterns.PatternType.release,
            &[_][]const u8{
                "napi_unref", "napi_delete_reference",
            },
            80,
            "nodejs",
        );
    }
};
