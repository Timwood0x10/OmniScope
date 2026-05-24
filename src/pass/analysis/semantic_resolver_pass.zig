//! Semantic Resolver Pass
//!
//! This pass implements the semantic resolution layer that processes
//! LLVM IR and applies language-specific patterns to resolve ownership
//! and safety semantics before heavy analysis passes.

const std = @import("std");
const PassContext = @import("../pass.zig").PassContext;
const DiagnosticWriter = @import("../pass.zig").DiagnosticWriter;

const resolution_engine = @import("../../semantics/resolution_engine.zig");
const ResolutionEngine = resolution_engine.ResolutionEngine;
const semantic_patterns = @import("../../semantics/semantic_patterns.zig");

const c = @import("../../ir/llvm_raw.zig").c;

/// Semantic resolver pass
pub const SemanticResolverPass = struct {
    pub const name = "SemanticResolver";
    pub const kind = @import("../pass.zig").PassKind.analysis;
    pub const deps = &[_][]const u8{};

    /// Run the semantic resolver pass
    pub fn run(ctx: *PassContext, diag: *DiagnosticWriter) !void {
        std.log.debug("[SemanticResolver] Starting semantic resolution...", .{});

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
                        if (@intFromPtr(c.LLVMIsACallInst(inst)) != 0) {
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

        const end_time = std.time.nanoTimestamp();
        const duration_ms = @as(f64, @floatFromInt(end_time - start_time)) / 1_000_000.0;

        // Log statistics
        const stats = engine.getStats();
        std.log.debug(
            "[SemanticResolver] Completed in {d:.1}ms: total_nodes={d}, resolutions={d}, patterns_applied={d}, allocs={d}, frees={d}, caller_semantics={d}",
            .{ duration_ms, stats.total_nodes, stats.resolutions_made, stats.patterns_applied, stats.allocations_tracked, stats.frees_tracked, engine.caller_semantics.count() },
        );

        // Store the resolution engine in context for later passes
        const engine_ptr = try ctx.allocator.create(ResolutionEngine);
        engine_ptr.* = engine;
        ctx.semantic_resolution = engine_ptr;

        // Note: We don't deinit the engine here since it's now owned by PassContext

        _ = diag;
    }

    /// Register built-in patterns for common allocation/release functions
    fn registerBuiltinPatterns(engine: *ResolutionEngine) !void {
        // C allocation patterns
        _ = try engine.registerPattern(
            "malloc_alloc",
            "C malloc allocation",
            semantic_patterns.PatternType.allocation,
            &[_][]const u8{ "malloc", "calloc", "realloc" },
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

        // Rust allocation patterns
        _ = try engine.registerPattern(
            "rust_alloc",
            "Rust heap allocation",
            semantic_patterns.PatternType.allocation,
            &[_][]const u8{ "__rust_alloc", "__rust_alloc_zeroed" },
            100,
            "rust",
        );
        _ = try engine.registerPattern(
            "rust_dealloc",
            "Rust heap release",
            semantic_patterns.PatternType.release,
            &[_][]const u8{"__rust_dealloc"},
            100,
            "rust",
        );
        _ = try engine.registerPattern(
            "rust_drop",
            "Rust Drop trait implementation",
            semantic_patterns.PatternType.release,
            &[_][]const u8{ "drop_in_place", "drop" },
            90,
            "rust",
        );

        // C++ allocation patterns
        _ = try engine.registerPattern(
            "cpp_new",
            "C++ new allocation",
            semantic_patterns.PatternType.allocation,
            &[_][]const u8{ "_Znwm", "_Znam" },
            100,
            "cpp",
        );
        _ = try engine.registerPattern(
            "cpp_delete",
            "C++ delete release",
            semantic_patterns.PatternType.release,
            &[_][]const u8{ "_ZdlPv", "_ZdaPv" },
            100,
            "cpp",
        );
    }
};
