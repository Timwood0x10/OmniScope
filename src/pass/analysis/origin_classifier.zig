//! OriginClassifierPass — Early Pipeline Function Origin Classification
//!
//! Classifies every function in the module using three layered signals:
//!   L1 — Linkage heuristic (O(1) per function)
//!   L2 — Debug origin / source path (O(1) per function)
//!   L3 — CallGraph reachability (O(V+E) one-time BFS)
//!
//! Writes results to PassContext.function_origin, which all downstream
//! passes query instead of calling noise_filter.classifyFunctionFull().
//!
//! Pipeline position: after zone-classifier, before all analysis passes.
//! No instruction-level scanning — only metadata and callgraph queries.

const std = @import("std");
const c = @import("../../ir/llvm_raw.zig").c;
const PassContext = @import("../pass.zig").PassContext;
const DiagnosticWriter = @import("../pass.zig").DiagnosticWriter;
const PassKind = @import("../pass.zig").PassKind;
const origin_classifier = @import("../../semantics/origin_classifier.zig");

pub const OriginClassifierPass = struct {
    pub const name = "origin-classifier";
    pub const kind = PassKind.foundation;
    // No hard deps — runs early, uses CallSiteIndex which is built
    // in Pipeline.run() before any pass executes.
    pub const deps = &[_][]const u8{};

    pub fn run(ctx: *PassContext, diag: *DiagnosticWriter) !void {
        if (ctx.module == null) return;
        const raw_mod = ctx.module.?.raw;

        const t0 = std.time.nanoTimestamp();

        // Phase 1: Classify every function using L1 + L2
        var func = c.LLVMGetFirstFunction(raw_mod);
        while (@intFromPtr(func) != 0) : (func = c.LLVMGetNextFunction(func)) {
            const func_ptr = @as(u64, @intFromPtr(func));
            const l1 = origin_classifier.classifyLinkage(func);
            const l2 = origin_classifier.classifyDebugOrigin(func);
            // L3 will be applied in Phase 2; for now, assume reachable
            const origin = origin_classifier.mergeLayers(l1, l2, true);
            try ctx.function_origin.put(func_ptr, origin);
        }

        // Phase 2: CallGraph reachability (L3)
        applyReachability(ctx);

        const elapsed_ms = @as(f64, @floatFromInt(std.time.nanoTimestamp() - t0)) / 1_000_000.0;

        // Statistics
        var stats = OriginStats{};
        var iter = ctx.function_origin.valueIterator();
        while (iter.next()) |origin| {
            stats.count(origin.*);
        }

        diag.info("[OriginClassifier] {d:.1} ms — classified {d} functions: user={d} dep={d} stdlib={d} gen={d} rt={d} unk={d}", .{
            elapsed_ms,
            stats.total(),
            stats.user,
            stats.dependency,
            stats.stdlib,
            stats.generated,
            stats.runtime,
            stats.unknown,
        });
    }
};

// ============================================================================
// L3: CallGraph Reachability
// ============================================================================

/// Apply forward reachability from root functions.
///
/// Roots are functions that are "meaningful starting points":
///   - extern "C" exports (FFI boundary producers)
///   - functions with user/dependency origin from L1+L2
///   - non-declaration functions that aren't compiler noise
///
/// Any function NOT reachable from roots AND classified as
/// stdlib/generated/runtime by L1/L2 will stay suppressed.
/// Reachable functions get promoted to user/dependency regardless of L1/L2.
fn applyReachability(ctx: *PassContext) void {
    // Build a caller→callees adjacency list from CallSiteIndex.
    // CallSiteIndex maps callee_name → [CallSite{caller_func, inst}]
    // We need caller_func → [callee_func] for forward walk.
    const allocator = ctx.allocator;

    // Step 1: Build forward adjacency list (caller_ptr → callee_ptrs)
    var forward_adj = std.AutoHashMap(u64, std.ArrayList(u64)).init(allocator);
    defer {
        var adj_iter = forward_adj.valueIterator();
        while (adj_iter.next()) |list| {
            list.deinit(allocator);
        }
        forward_adj.deinit();
    }

    // Populate forward_adj from CallSiteIndex
    var csi_iter = ctx.CallSiteIndex.map.iterator();
    while (csi_iter.next()) |entry| {
        const callee_name = entry.key_ptr.*;
        const call_sites = entry.value_ptr.*;

        // Resolve callee_name to a function pointer
        const raw_mod = ctx.module.?.raw;
        const callee_func = c.LLVMGetNamedFunction(raw_mod, callee_name.ptr);
        if (@intFromPtr(callee_func) == 0) continue;
        const callee_ptr = @as(u64, @intFromPtr(callee_func));

        for (call_sites.items) |site| {
            const caller_ptr = site.caller_func;
            const gop = forward_adj.getOrPut(caller_ptr) catch continue;
            if (!gop.found_existing) {
                gop.value_ptr.* = std.ArrayList(u64).initCapacity(allocator, 4) catch continue;
            }
            gop.value_ptr.append(allocator, callee_ptr) catch {};
        }
    }

    // Step 2: Collect roots — functions that are entry points
    var reachable = std.AutoHashMap(u64, void).init(allocator);
    defer reachable.deinit();

    // Roots: user/dependency origin functions (L1+L2 said they matter)
    var origin_iter = ctx.function_origin.iterator();
    while (origin_iter.next()) |entry| {
        const func_ptr = entry.key_ptr.*;
        const origin = entry.value_ptr.*;
        if (origin == .user or origin == .dependency) {
            reachable.put(func_ptr, {}) catch {};
        }
    }

    // Roots: extern "C" exported functions (potential FFI boundary)
    var func = c.LLVMGetFirstFunction(ctx.module.?.raw);
    while (@intFromPtr(func) != 0) : (func = c.LLVMGetNextFunction(func)) {
        if (c.LLVMIsDeclaration(func) != 0) continue;
        const linkage = c.LLVMGetLinkage(func);
        if (linkage == c.LLVMExternalLinkage) {
            // Externally visible function — potential API entry point
            const func_ptr = @as(u64, @intFromPtr(func));
            reachable.put(func_ptr, {}) catch {};
        }
    }

    // Step 3: Forward BFS from roots
    var queue = std.ArrayList(u64).initCapacity(allocator, 64) catch return;
    defer queue.deinit(allocator);

    var root_iter = reachable.keyIterator();
    while (root_iter.next()) |ptr| {
        queue.append(allocator, ptr.*) catch {};
    }

    var head: usize = 0;
    while (head < queue.items.len) : (head += 1) {
        const caller = queue.items[head];
        const adj_entry = forward_adj.get(caller) orelse continue;
        for (adj_entry.items) |callee| {
            const gop = reachable.getOrPut(callee) catch continue;
            if (!gop.found_existing) {
                queue.append(allocator, callee) catch {};
            }
        }
    }

    // Step 4: Apply reachability results
    // If a function is NOT reachable AND was classified as noise by L1/L2,
    // keep its noise classification. If it IS reachable, promote it.
    var apply_iter = ctx.function_origin.iterator();
    while (apply_iter.next()) |entry| {
        const func_ptr = entry.key_ptr.*;
        const is_reachable = reachable.contains(func_ptr);

        if (is_reachable) {
            // Reachable — if L1/L2 said noise, promote to user/dependency
            const current = entry.value_ptr.*;
            switch (current) {
                .stdlib, .generated, .runtime => {
                    // Reachable noise — likely a dependency that participates
                    // in ownership flow (e.g., ring, libsqlite3-sys).
                    entry.value_ptr.* = .dependency;
                },
                .user, .dependency, .unknown => {
                    // Already kept — no change needed
                },
            }
        } else {
            // Not reachable — if L1/L2 said noise, keep suppressed.
            // If L1/L2 said user but it's unreachable, it's probably a
            // dead function — but we conservatively keep it as .unknown.
            const current = entry.value_ptr.*;
            switch (current) {
                .user => {
                    // User code but unreachable — likely dead code.
                    // Conservative: keep as .unknown (will be analyzed).
                    entry.value_ptr.* = .unknown;
                },
                .dependency => {
                    // Dependency but unreachable — likely internal dep code.
                    entry.value_ptr.* = .unknown;
                },
                .stdlib, .generated, .runtime => {
                    // Already suppressed — no change needed
                },
                .unknown => {
                    // Already conservative — no change
                },
            }
        }
    }
}

// ============================================================================
// Statistics
// ============================================================================

const OriginStats = struct {
    user: usize = 0,
    dependency: usize = 0,
    stdlib: usize = 0,
    generated: usize = 0,
    runtime: usize = 0,
    unknown: usize = 0,

    fn count(self: *OriginStats, origin: origin_classifier.FunctionOrigin) void {
        switch (origin) {
            .user => self.user += 1,
            .dependency => self.dependency += 1,
            .stdlib => self.stdlib += 1,
            .generated => self.generated += 1,
            .runtime => self.runtime += 1,
            .unknown => self.unknown += 1,
        }
    }

    fn total(self: OriginStats) usize {
        return self.user + self.dependency + self.stdlib + self.generated + self.runtime + self.unknown;
    }
};
