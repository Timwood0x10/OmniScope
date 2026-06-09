//! SurfaceClassifierPass — Early Pipeline Function Surface Classification
//!
//! Classifies every function in the module using five layered signals:
//!   L0 — Mangled name heuristic (pure string match, zero LLVM calls)
//!   L1 — Linkage heuristic (O(1) per function)
//!   L2 — Debug origin / source path (O(1) per function, needs debug metadata)
//!   L3 — CallGraph reachability (O(V+E) one-time BFS)
//!   L4a— FFI Boundary detection (cross-ABI: extern "C", #[no_mangle])
//!   L4b— Library Export detection (same-language pub fn, NOT security surface)
//!
//! Key architectural decision:
//!   OLD: external linkage = boundary → 1331 wasmtime fns bypassed all filters
//!   NEW: only unmangled/CCallConv/section-exported = real FFI boundary
//!        mangled + external linkage = library export → treated as dependency
//!
//! Writes results to PassContext.function_surface, which all downstream
//! passes query instead of calling noise_filter.classifyFunctionFull().
//!
//! Pipeline position: after zone-classifier, before all analysis passes.
//! No instruction-level scanning — only metadata and callgraph queries.

const std = @import("std");
const c = @import("../../ir/llvm_raw.zig").c;
const log = @import("../../common/log.zig");
const PassContext = @import("../pass.zig").PassContext;
const DiagnosticWriter = @import("../pass.zig").DiagnosticWriter;
const PassKind = @import("../pass.zig").PassKind;
const surface = @import("../../semantics/surface_classifier/surface_classifier.zig");
const boundary = @import("../../semantics/surface_classifier/boundary.zig");
const platform_surface = @import("../../semantics/surface_classifier/platform.zig");

pub const SurfaceClassifierPass = struct {
    pub const name = "surface-classifier";
    pub const kind = PassKind.foundation;
    pub const deps = &[_][]const u8{};

    pub fn run(ctx: *PassContext, diag: *DiagnosticWriter) !void {
        if (ctx.module == null) return;
        const raw_mod = ctx.module.?.raw;

        const t0 = std.time.nanoTimestamp();

        // Phase 1: Classify every function using L0 + L1 + L2 + L4
        var l0_hits: usize = 0;
        var l1_hits: usize = 0;
        var l2_hits: usize = 0;
        var l2_no_debug: usize = 0;
        var l2_debug_but_unknown: usize = 0;
        var ffi_boundary_count: usize = 0; // Real cross-ABI boundaries
        var lib_export_count: usize = 0; // Same-language pub fn (not FFI)
        var logged_count: usize = 0;
        var phase1_stats = SurfaceStats{};

        var func = c.LLVMGetFirstFunction(raw_mod);
        while (@intFromPtr(func) != 0) : (func = c.LLVMGetNextFunction(func)) {
            const func_ptr = @as(u64, @intFromPtr(func));

            // Get function name once — used by L0 and for logging
            const func_name_ptr = c.LLVMGetValueName(func);
            const func_name = if (@intFromPtr(func_name_ptr) != 0) std.mem.span(func_name_ptr) else "<unnamed>";

            // L4a: FFI Boundary detection (strict — only cross-ABI)
            // L4b: Library Export detection (mangled + external, not FFI)
            //
            // P0-Fix1: Pure C/C++ modules have no FFI concept — all functions
            // are within the same language. Skip boundary detection entirely
            // to prevent false positives on external linkage C functions.
            const is_ffi_boundary = if (!ctx.isCModule())
                boundary.detectBoundaryFromLLVM(func, ctx.module_language.language)
            else
                false;
            const is_lib_export = if (!ctx.isCModule())
                boundary.detectLibraryExport(func, ctx.module_language.language)
            else
                false;

            // L4c: Caller-side FFI detection (calls external FFI functions)
            // Complements callee-side detection for modules that IMPORT FFI functions
            // Example: Rust module calling c_hash() from C bridge
            const is_ffi_caller = if (!ctx.isCModule())
                boundary.detectCallerSideFFI(func, raw_mod)
            else
                false;
            const is_real_ffi_boundary = is_ffi_boundary or is_ffi_caller;

            if (is_real_ffi_boundary) ffi_boundary_count += 1;
            if (is_lib_export) lib_export_count += 1;

            // L0: Mangled name heuristic (cheapest — pure string match)
            const l0_hint = surface.classifyMangledNameDiagnostic(func_name);

            // L1: Linkage heuristic (O(1) LLVM field read)
            const l1_hint = surface.classifyLinkage(func);

            // L2: Debug origin (requires debug metadata in IR)
            const l2_hint = surface.classifyDebugOriginDiagnostic(func, func_name);

            // L-Platform: Platform-specific runtime shim / toolchain detection.
            // Uses target triple, symbol naming conventions, and known runtime patterns
            // to identify compiler-generated functions that should be skipped.
            var plat_hint: ?platform_surface.PlatformSurfaceHint = null;
            if (ctx.platform_profile) |*prof| {
                plat_hint = platform_surface.generatePlatformHint(func_name, prof);
            }

            // Merge all layers into final decision
            //
            // Critical: is_real_ffi_boundary (not is_lib_export) controls the
            // .boundary surface. Library exports are just dependency code.
            var surf = surface.mergeLayers(l0_hint, l1_hint, l2_hint, true, is_real_ffi_boundary);

            // Apply platform hint (P8: boundary and unknown take priority)
            if (plat_hint) |*ph| {
                surf = platform_surface.mergePlatformHint(surf, ph.*, is_real_ffi_boundary);
                if (logged_count < 30) {
                    log.debug("[Platform-Layer] {s}: {s} (conf={s}) -> {s}", .{
                        func_name,
                        @tagName(ph.suggested_surface),
                        @tagName(ph.confidence),
                        @tagName(surf),
                    });
                }
            }

            // Track per-layer hit rates
            if (l0_hint != null) l0_hits += 1;
            if (l1_hint != null) l1_hits += 1;
            if (l2_hint != null) l2_hits += 1;
            if (l2_hint == null) {
                const sp = c.LLVMGetSubprogram(func);
                if (@intFromPtr(sp) == 0) {
                    l2_no_debug += 1;
                } else {
                    l2_debug_but_unknown += 1;
                }
            }

            try ctx.function_surface.put(func_ptr, surf);

            // Verbose: log first 30 functions with per-layer details (debug level)
            if (logged_count < 30) {
                const l0_str = if (l0_hint) |h| h.surface.toString() else "null";
                const l1_str = if (l1_hint) |h| h.surface.toString() else "null";
                const l2_str = if (l2_hint) |h| h.surface.toString() else "null";
                const bnd_str = if (is_real_ffi_boundary) "FFI" else if (is_lib_export) "LIB" else "--";
                const caller_str = if (is_ffi_caller) "+CALLER" else "";
                log.debug("[SurfaceClassifier] {s}: L0={s} L1={s} L2={s} bnd={s}{s} => {s}", .{
                    func_name, l0_str, l1_str, l2_str, bnd_str, caller_str, surf.toString(),
                });
                logged_count += 1;
            }
            phase1_stats.count(surf);
        }

        // Phase 1 summary (info level — always visible)
        log.debug("[SurfaceClassifier-LAYERS] L0={d} L1={d} L2={d} L2_no_dbg={d} L2_dbg_unk={d} FFI_BND={d} LIB_EXP={d}", .{
            l0_hits,
            l1_hits,
            l2_hits,
            l2_no_debug,
            l2_debug_but_unknown,
            ffi_boundary_count,
            lib_export_count,
        });
        log.debug("[SurfaceClassifier-PHASE1] user={d} dep={d} bnd={d} stdlib={d} gen={d} rt={d} unk={d}", .{
            phase1_stats.user_code,
            phase1_stats.dependency,
            phase1_stats.boundary,
            phase1_stats.standard_library,
            phase1_stats.compiler_generated,
            phase1_stats.runtime,
            phase1_stats.unknown,
        });

        // ── FFI Early Exit ──────────────────────────────────────────────
        // If no FFI boundary exists in this module, there's no cross-language
        // attack surface. The module is a self-contained Rust/C++/Zig binary
        // with no extern "C" exports → skip heavy analysis entirely.
        //
        // This saves massive resources on single-language binaries where
        // the old pipeline would still analyze 1331 "boundary" functions.
        if (ffi_boundary_count == 0) {
            log.debug("[SurfaceClassifier-FFI] No FFI boundary detected ({d} lib_exports). Skipping cross-language analysis.", .{lib_export_count});
            // Mark context: no FFI analysis needed
            ctx.has_ffi_boundary = false;

            const elapsed_ms = @as(f64, @floatFromInt(std.time.nanoTimestamp() - t0)) / 1_000_000.0;
            var stats = SurfaceStats{};
            var iter = ctx.function_surface.valueIterator();
            while (iter.next()) |s| {
                stats.count(s.*);
            }
            diag.info("[SurfaceClassifier] {d:.1} ms — NO FFI SURFACE — {d} functions: bnd={d} dep={d} unk={d} stdlib={d} gen={d} rt={d}", .{
                elapsed_ms,
                stats.total(),
                stats.boundary,
                stats.dependency,
                stats.unknown,
                stats.standard_library,
                stats.compiler_generated,
                stats.runtime,
            });
            return; // Early exit — skip Phase 3 and heavy analysis
        }

        log.debug("[SurfaceClassifier-FFI] {d} FFI boundaries detected — proceeding with full analysis.", .{ffi_boundary_count});
        ctx.has_ffi_boundary = true;

        // Phase 2: CallGraph reachability (L3) — only when FFI exists
        applyReachability(ctx);

        // Post-L3 statistics
        var post_l3_stats = SurfaceStats{};
        var post_iter = ctx.function_surface.valueIterator();
        while (post_iter.next()) |s| {
            post_l3_stats.count(s.*);
        }

        log.debug("[SurfaceClassifier-POST-L3] user={d} dep={d} bnd={d} stdlib={d} gen={d} rt={d} unk={d}", .{
            post_l3_stats.user_code,
            post_l3_stats.dependency,
            post_l3_stats.boundary,
            post_l3_stats.standard_library,
            post_l3_stats.compiler_generated,
            post_l3_stats.runtime,
            post_l3_stats.unknown,
        });

        log.debug("[SurfaceClassifier-L3-DELTA] stdlib:{d}->{d} gen:{d}->{d} rt:{d}->{d} unk:{d}->{d} dep:{d}->{d}", .{
            phase1_stats.standard_library,
            post_l3_stats.standard_library,
            phase1_stats.compiler_generated,
            post_l3_stats.compiler_generated,
            phase1_stats.runtime,
            post_l3_stats.runtime,
            phase1_stats.unknown,
            post_l3_stats.unknown,
            phase1_stats.dependency,
            post_l3_stats.dependency,
        });

        const elapsed_ms = @as(f64, @floatFromInt(std.time.nanoTimestamp() - t0)) / 1_000_000.0;

        // Final statistics
        var stats = SurfaceStats{};
        var iter = ctx.function_surface.valueIterator();
        while (iter.next()) |s| {
            stats.count(s.*);
        }

        // Calculate noise filter efficiency
        const total = stats.total();
        const skipped = stats.standard_library + stats.compiler_generated + stats.runtime;
        const skip_pct: f64 = if (total > 0) @as(f64, @floatFromInt(skipped)) / @as(f64, @floatFromInt(total)) * 100.0 else 0.0;

        diag.info("[SurfaceClassifier] {d:.1} ms — {d} funcs: FFI_bnd={d} lib_exp={d} user={d} dep={d} stdlib={d} gen={d} rt={d} unk={d} [noise filtered: {d:.1}%]", .{
            elapsed_ms,
            total,
            ffi_boundary_count,
            lib_export_count,
            stats.user_code,
            stats.dependency,
            stats.standard_library,
            stats.compiler_generated,
            stats.runtime,
            stats.unknown,
            skip_pct,
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

    // Roots: user/dependency/boundary functions from Phase 1
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
