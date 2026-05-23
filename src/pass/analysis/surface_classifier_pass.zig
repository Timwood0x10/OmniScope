//! SurfaceClassifierPass — Early Pipeline Function Surface Classification
//!
//! Classifies every function in the module using four layered signals:
//!   L1 — Linkage heuristic (O(1) per function)
//!   L2 — Debug origin / source path (O(1) per function)
//!   L3 — CallGraph reachability (O(V+E) one-time BFS)
//!   L4 — Boundary detection (exported symbols -> boundary)
//!
//! Writes results to PassContext.function_surface, which all downstream
//! passes query instead of calling noise_filter.classifyFunctionFull().
//!
//! Pipeline position: after zone-classifier, before all analysis passes.
//! No instruction-level scanning — only metadata and callgraph queries.

const std = @import("std");
const c = @import("../../ir/llvm_raw.zig").c;
const PassContext = @import("../pass.zig").PassContext;
const DiagnosticWriter = @import("../pass.zig").DiagnosticWriter;
const PassKind = @import("../pass.zig").PassKind;
const surface = @import("../../semantics/surface_classifier/surface_classifier.zig");

pub const SurfaceClassifierPass = struct {
    pub const name = "surface-classifier";
    pub const kind = PassKind.foundation;
    pub const deps = &[_][]const u8{};

    pub fn run(ctx: *PassContext, diag: *DiagnosticWriter) !void {
        if (ctx.module == null) return;
        const raw_mod = ctx.module.?.raw;

        const t0 = std.time.nanoTimestamp();

        // Phase 1: Classify every function using L1 + L2 + L4 (boundary)
        var func = c.LLVMGetFirstFunction(raw_mod);
        while (@intFromPtr(func) != 0) : (func = c.LLVMGetNextFunction(func)) {
            const func_ptr = @as(u64, @intFromPtr(func));
            const is_boundary = surface.detectBoundaryFromLLVM(func);
            const surf = surface.classifyFunction(func, is_boundary);
            try ctx.function_surface.put(func_ptr, surf);
        }

        // Phase 2: CallGraph reachability (L3)
        applyReachability(ctx);

        const elapsed_ms = @as(f64, @floatFromInt(std.time.nanoTimestamp() - t0)) / 1_000_000.0;

        // Statistics
        var stats = SurfaceStats{};
        var iter = ctx.function_surface.valueIterator();
        while (iter.next()) |s| {
            stats.count(s.*);
        }

        diag.info("[SurfaceClassifier] {d:.1} ms — {d} functions: user={d} dep={d} bnd={d} stdlib={d} gen={d} rt={d} unk={d}", .{
            elapsed_ms,
            stats.total(),
            stats.user_code,
            stats.dependency,
            stats.boundary,
            stats.standard_library,
            stats.compiler_generated,
            stats.runtime,
            stats.unknown,
        });
    }
};

// ============================================================================
// L3: CallGraph Reachability
// ============================================================================

/// Apply forward reachability from root functions.
fn applyReachability(ctx: *PassContext) void {
    const allocator = ctx.allocator;

    // Step 1: Build forward adjacency list (caller_ptr -> callee_ptrs)
    var forward_adj = std.AutoHashMap(u64, std.ArrayList(u64)).init(allocator);
    defer {
        var adj_iter = forward_adj.valueIterator();
        while (adj_iter.next()) |list| {
            list.deinit(allocator);
        }
        forward_adj.deinit();
    }

    var csi_iter = ctx.CallSiteIndex.map.iterator();
    while (csi_iter.next()) |entry| {
        const callee_name = entry.key_ptr.*;
        const call_sites = entry.value_ptr.*;

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

    // Step 2: Collect roots
    var reachable = std.AutoHashMap(u64, void).init(allocator);
    defer reachable.deinit();

    // Roots: user/dependency/boundary functions
    var origin_iter = ctx.function_surface.iterator();
    while (origin_iter.next()) |entry| {
        const surf = entry.value_ptr.*;
        if (surf == .user_code or surf == .dependency or surf == .boundary) {
            reachable.put(entry.key_ptr.*, {}) catch {};
        }
    }

    // Roots: externally visible defined functions
    var func = c.LLVMGetFirstFunction(ctx.module.?.raw);
    while (@intFromPtr(func) != 0) : (func = c.LLVMGetNextFunction(func)) {
        if (c.LLVMIsDeclaration(func) != 0) continue;
        if (c.LLVMGetLinkage(func) == c.LLVMExternalLinkage) {
            reachable.put(@as(u64, @intFromPtr(func)), {}) catch {};
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
    var apply_iter = ctx.function_surface.iterator();
    while (apply_iter.next()) |entry| {
        const is_reachable = reachable.contains(entry.key_ptr.*);

        if (is_reachable) {
            const current = entry.value_ptr.*;
            switch (current) {
                .standard_library, .compiler_generated, .runtime => {
                    entry.value_ptr.* = .dependency;
                },
                .user_code, .dependency, .boundary, .unknown => {},
            }
        } else {
            const current = entry.value_ptr.*;
            switch (current) {
                .user_code, .dependency => {
                    entry.value_ptr.* = .unknown;
                },
                .standard_library, .compiler_generated, .runtime, .boundary, .unknown => {},
            }
        }
    }
}

// ============================================================================
// Statistics
// ============================================================================

const SurfaceStats = struct {
    user_code: usize = 0,
    dependency: usize = 0,
    boundary: usize = 0,
    standard_library: usize = 0,
    compiler_generated: usize = 0,
    runtime: usize = 0,
    unknown: usize = 0,

    fn count(self: *SurfaceStats, surf: surface.FunctionSurface) void {
        switch (surf) {
            .user_code => self.user_code += 1,
            .dependency => self.dependency += 1,
            .boundary => self.boundary += 1,
            .standard_library => self.standard_library += 1,
            .compiler_generated => self.compiler_generated += 1,
            .runtime => self.runtime += 1,
            .unknown => self.unknown += 1,
        }
    }

    fn total(self: SurfaceStats) usize {
        return self.user_code + self.dependency + self.boundary +
            self.standard_library + self.compiler_generated + self.runtime + self.unknown;
    }
};
