//! C++ False Positive Reduction — Detection Functions
//!
//! Extracted from cpp_fp_reduction.zig per rules.md line limit (≤800 lines).
//! Contains core memory safety detection passes:
//!   - detectDoubleFree(): Double-free detection with control-flow awareness
//!   - detectMemoryLeaks(): Memory leak detection with reverse BFS optimization
//!
//! Log prefix: [cpp-fp-detect]

const std = @import("std");
const c = @import("../ir/llvm_raw.zig").c;
const ffi_language_classifier = @import("../pass/analysis/ffi/ffi_language_classifier.zig");

const PassContext = @import("../pass/pass.zig").PassContext;
const DiagnosticWriter = @import("../pass/pass.zig").DiagnosticWriter;
const Issue = @import("../diag/issue.zig").Issue;
const Severity = @import("../diag/issue.zig").Severity;
const IssueCandidate = @import("../pass/analysis/resource/issue_candidate_builder.zig").IssueCandidate;
const Confidence = @import("../diag/issue.zig").Confidence;
const Location = @import("../diag/issue.zig").Location;
const ownership_types = @import("ownership_types.zig");
const AllocSite = ownership_types.AllocSite;
const FreeSite = ownership_types.FreeSite;
const OwnershipStats = ownership_types.OwnershipStats;

// Helpers from centralized modules
const cpp_helpers = @import("cpp_fp_helpers.zig");
const cpp_types = @import("cpp_fp_types.zig");

const isStlInternalFunction = cpp_helpers.isStlInternalFunction;
const isCppSpecialMemberFunction = cpp_helpers.isCppSpecialMemberFunction;
const is_likely_intentional_pattern = cpp_helpers.is_likely_intentional_pattern;
const isFactoryFunction = cpp_helpers.isFactoryFunction;
const isCppAbiInternalFunction = cpp_helpers.isCppAbiInternalFunction;
const isMeyersSingletonPattern = cpp_helpers.isMeyersSingletonPattern;
const isCppInternalLeakPattern = cpp_helpers.isCppInternalLeakPattern;

const PtrInfo = cpp_types.PtrInfo;
const isLikelyStructMemberOwnership = cpp_types.isLikelyStructMemberOwnership;

/// Detect double-free: same pointer freed multiple times.
/// P0-B Enhanced: Control-flow aware via basic_block_id tracking.
///
/// Key insight (from SQLite source-level verification):
///   - Same-BB double-free = REAL bug (sequential free() calls)
///   - Different-BB multi-free = cleanup paths (each error branch frees, NOT a bug)
///
/// v0.1.7 FIX: Dual-source deduplication.
/// MemoryGraph.trackFree() sync (Source 1) + IR-scan (Source 3) may both create
/// FreeSite entries for the same LLVM instruction. Without deduplication, every
/// real free appears twice → 100% false-positive rate on double-free detection.
/// Fix: group by (ptr_value_id, inst_id) to eliminate dual-source duplicates.
pub fn detectDoubleFree(
    ctx: *PassContext,
    free_map: *std.AutoHashMap(u32, *FreeSite),
    stats: *OwnershipStats,
    diag: *DiagnosticWriter,
) !void {
    if (free_map.count() == 0) {
        diag.debug("DOUBLE-FREE: No free sites, skipping", .{});
        return;
    }

    if (free_map.count() > 500) {
        diag.debug("DOUBLE-FREE: Skipped (too many free sites: {d})", .{free_map.count()});
        return;
    }

    // Per-ptr tracking: count + unique BB set + first function name
    var ptr_info_map = std.AutoHashMap(u32, PtrInfo).init(free_map.allocator);
    defer {
        var iter = ptr_info_map.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.deinit();
        }
        ptr_info_map.deinit();
    }

    // Collect free operations with RAII filtering + BB tracking + dedup
    var free_iter = free_map.iterator();
    while (free_iter.next()) |entry| {
        const free_info = entry.value_ptr.*;
        const ptr_id = free_info.ptr_value_id;

        if (isStlInternalFunction(free_info.func_name)) continue;
        if (isCppSpecialMemberFunction(free_info.func_name)) continue;
        const func_name_ptr = @intFromPtr(free_info.func_name.ptr);
        if (ctx.raii_func_set.contains(func_name_ptr)) continue;

        // DEDUP: Skip if we already counted this exact (ptr, inst) pair.
        const gop_result = try ptr_info_map.getOrPut(ptr_id);
        if (!gop_result.found_existing) {
            gop_result.value_ptr.* = try PtrInfo.init(free_map.allocator, free_info.func_name);
        }
        const info = gop_result.value_ptr;

        // Only increment count if this is a UNIQUE (ptr_id, inst_id) pair.
        const inst_id = free_info.inst_id;
        if (info.inst_set.contains(inst_id)) {
            diag.debug("DF-DEDUP: Skipping duplicate free for ptr={d} inst={d} in {s}", .{ ptr_id, inst_id, free_info.func_name });
            continue;
        }
        info.inst_set.put(inst_id, {}) catch {};
        info.count += 1;
        info.bb_set.put(free_info.bb_id, {}) catch {};
    }

    // Analyze each pointer with multiple frees
    var count_iter = ptr_info_map.iterator();
    while (count_iter.next()) |count_entry| {
        const alloc_id = count_entry.key_ptr.*;
        const info = count_entry.value_ptr.*;
        const free_cnt = info.count;
        const unique_bbs = info.bb_set.count();

        if (free_cnt > 5) continue;

        if (free_cnt > 1) {
            const first_func = info.first_func;

            const is_mangled = (std.mem.indexOf(u8, first_func, "_ZN") != null or
                std.mem.indexOf(u8, first_func, "$") != null or
                std.mem.indexOf(u8, first_func, "_R") != null);
            if (is_mangled) continue;

            // SRT filter: skip semantically resolved release functions
            if (ctx.semantic_resolution) |engine| {
                if (engine.isSemanticallyRelease(first_func)) {
                    diag.debug("DOUBLE-FREE-SKIP: {s} is semantically resolved as release — language-guaranteed", .{first_func});
                    continue;
                }
            }

            // P0-B Core Logic: Control-Flow Awareness
            const is_same_bb = (unique_bbs == 1);

            if (!is_same_bb) {
                diag.debug("DOUBLE-FREE-SKIP: {d} frees of alloc {d} in {d} different BBs ({s}) — multi-path cleanup", .{ free_cnt, alloc_id, unique_bbs, first_func });
                continue;
            }

            // P2 FIX: Only report for pointers on danger paths
            const on_danger = ctx.isOnDangerPathFull(@as(u64, alloc_id));
            if (!on_danger) {
                diag.debug("DOUBLE-FREE-SKIP: alloc {d} not on danger path (pure internal)", .{alloc_id});
                continue;
            }

            // P2 FIX: Validate with MemoryGraph.isDoubleFreedOnSamePath
            const mg_double_freed = ctx.memory_graph.isDoubleFreedOnSamePath(@as(u64, alloc_id));
            if (!mg_double_freed) {
                diag.debug("DOUBLE-FREE-SKIP: alloc {d} not confirmed by MemoryGraph (multi-path cleanup)", .{alloc_id});
                continue;
            }

            // BB info validation: skip if all bb_id=0
            if (unique_bbs == 1) {
                var all_bb_zero = true;
                var check_iter = free_map.iterator();
                outer: while (check_iter.next()) |check_entry| {
                    const check_info = check_entry.value_ptr.*;
                    if (check_info.ptr_value_id == alloc_id) {
                        if (check_info.bb_id != 0) {
                            all_bb_zero = false;
                            break :outer;
                        }
                    }
                }
                if (all_bb_zero) {
                    diag.debug("DOUBLE-FREE-SKIP: alloc {d} all free sites have bb_id=0 (BB info missing)", .{alloc_id});
                    continue;
                }
            }

            stats.double_frees += 1;
                    // P20: Structured candidate evidence
                    var df_cand = IssueCandidate.init(ctx.allocator, .double_release, 0.92);
                    df_cand.func_name = first_func;
                    df_cand.addEvidence("Same-BB double-free detected") catch {};

            const severity: Severity = .high;
            const confidence: f32 = 0.92;
            const msg = std.fmt.allocPrint(ctx.allocator, "DOUBLE-FREE: Allocation {d} freed {d} times in SAME basic block ({s})", .{ alloc_id, free_cnt, first_func }) catch {
                ctx.addIssue(&Issue.init(.double_free, "Double-free detected", Location.init(first_func), severity, confidence)) catch {
                    diag.warn("Failed to register critical double_free issue", .{});
                };
                diag.err("DOUBLE-FREE [HIGH]: Allocation {d} freed {d} times in SAME basic block ({s}) — confirmed double-free", .{ alloc_id, free_cnt, first_func });
                diag.err("  Risk: Heap corruption, use-after-free, security vulnerability", .{});
                continue;
            };

            ctx.addIssue(&Issue.init(.double_free, msg, Location.init(first_func), severity, confidence)) catch {
                diag.warn("Failed to register double_free issue with message", .{});
            };
            diag.err("DOUBLE-FREE [HIGH]: Allocation {d} freed {d} times in SAME basic block ({s}) — confirmed double-free", .{ alloc_id, free_cnt, first_func });
            diag.err("  Risk: Heap corruption, use-after-free, security vulnerability", .{});
        }
    }
}

/// Detect memory leaks: allocations that are never freed.
/// Uses reverse BFS optimization for O(E) pre-computation instead of O(N×E).
pub fn detectMemoryLeaks(
    ctx: *PassContext,
    alloc_map: *std.AutoHashMap(u32, *AllocSite),
    free_map: *std.AutoHashMap(u32, *FreeSite),
    flow_graph: *std.AutoHashMap(u32, std.AutoHashMap(u32, void)),
    stats: *OwnershipStats,
    diag: *DiagnosticWriter,
) void {
    var reported_func_ptrs = std.AutoHashMap(usize, void).init(alloc_map.allocator);
    defer reported_func_ptrs.deinit();

    // PERF: Pre-compute which nodes can reach a free site via reverse BFS.
    var can_reach_free = std.AutoHashMap(u32, void).init(alloc_map.allocator);
    defer can_reach_free.deinit();
    {
        // Build reverse edge map: target → list of sources
        var reverse_map = std.AutoHashMap(u32, std.ArrayList(u32)).init(alloc_map.allocator);
        defer {
            var ri = reverse_map.iterator();
            while (ri.next()) |entry| {
                entry.value_ptr.deinit(alloc_map.allocator);
            }
            reverse_map.deinit();
        }
        var fg_iter = flow_graph.iterator();
        while (fg_iter.next()) |fg_entry| {
            const src = fg_entry.key_ptr.*;
            var target_iter = fg_entry.value_ptr.iterator();
            while (target_iter.next()) |target_entry| {
                const target = target_entry.key_ptr.*;
                const gop = reverse_map.getOrPut(target) catch continue;
                if (!gop.found_existing) {
                    gop.value_ptr.* = std.ArrayList(u32).initCapacity(alloc_map.allocator, 4) catch continue;
                }
                gop.value_ptr.append(alloc_map.allocator, src) catch {};
            }
        }

        // Seed: all free site ptr_value_ids and inst_ids can reach free
        var free_iter = free_map.iterator();
        while (free_iter.next()) |entry| {
            can_reach_free.put(entry.value_ptr.*.ptr_value_id, {}) catch {};
            can_reach_free.put(entry.value_ptr.*.inst_id, {}) catch {};
        }

        // Reverse BFS from free sites using reverse_map
        var frontier = std.ArrayList(u32).initCapacity(alloc_map.allocator, can_reach_free.count()) catch return;
        defer frontier.deinit(alloc_map.allocator);
        {
            var seed_iter = can_reach_free.iterator();
            while (seed_iter.next()) |entry| {
                frontier.append(alloc_map.allocator, entry.key_ptr.*) catch {};
            }
        }
        while (frontier.items.len > 0) {
            const current = frontier.orderedRemove(0);
            if (reverse_map.get(current)) |sources| {
                for (sources.items) |src| {
                    if (!can_reach_free.contains(src)) {
                        can_reach_free.put(src, {}) catch {};
                        frontier.append(alloc_map.allocator, src) catch {};
                    }
                }
            }
        }
    }

    var alloc_iter = alloc_map.iterator();
    while (alloc_iter.next()) |entry| {
        const alloc_info = entry.value_ptr.*;

        if (alloc_info.transferred) continue;

        if (isStlInternalFunction(alloc_info.func_name)) continue;

        if (isCppSpecialMemberFunction(alloc_info.func_name)) continue;

        const func_name_ptr = @intFromPtr(alloc_info.func_name.ptr);
        if (ctx.raii_func_set.contains(func_name_ptr)) continue;

        if (isCppAbiInternalFunction(alloc_info.func_name)) continue;

        if (isMeyersSingletonPattern(alloc_info.func_name)) continue;

        const meyers_ptr = @intFromPtr(alloc_info.func_name.ptr);
        if (ctx.meyers_singleton_set.contains(meyers_ptr)) continue;

        const rc_ptr = @intFromPtr(alloc_info.func_name.ptr);
        if (ctx.rc_container_func_set.contains(rc_ptr)) continue;

        // L9: Rust FFI ownership transfer pairing check
        const func_name_str = alloc_info.func_name;
        if (ctx.rust_into_raw_set.contains(func_name_str)) {
            if (ctx.rust_from_raw_set.count() > 0) {
                continue;
            }
        }

        // SRT filter: skip semantically resolved release functions
        if (ctx.semantic_resolution) |engine| {
            if (engine.isSemanticallyRelease(alloc_info.func_name)) {
                diag.debug("LEAK-SKIP: {s} is semantically resolved as release — allocation inside destructor", .{alloc_info.func_name});
                continue;
            }
        }

        // OPT: Use pre-computed can_reach_free set instead of per-alloc BFS
        const has_free_path = can_reach_free.contains(alloc_info.inst_id) or
            can_reach_free.contains(alloc_info.ptr_value_id);
        if (!has_free_path) {
            // P18-FP3: Factory function pattern — alloc result returned to caller.
            // Not a leak if the function name indicates ownership transfer.
            // Example: XXH32_createState() { return malloc(...); } → caller frees
            if (isFactoryFunction(alloc_info.func_name)) {
                diag.debug("LEAK-SKIP: {s} is factory function — caller owns result", .{alloc_info.func_name});
                continue;
            }
            if (is_likely_intentional_pattern(alloc_info.func_name)) {
                continue;
            }
            if (isLikelyStructMemberOwnership(alloc_info.func_name)) {
                continue;
            }
            if (alloc_info.stored_to_struct_field) {
                continue;
            }
            // P2 FIX: Use MemoryGraph.isOnDangerPathFull for filtering
            const on_danger_path = ctx.isOnDangerPathFull(@as(u64, alloc_info.inst_id));
            if (!on_danger_path) {
                // C++ internal leak bypass
                const is_cpp_module = ctx.module_language.language == .cpp or
                    ctx.module_language.language == .unknown;
                const looks_like_cpp_alloc = std.mem.indexOf(u8, alloc_info.func_name, "_ZN") != null or
                    std.mem.indexOf(u8, alloc_info.func_name, "_Z") != null;
                if (is_cpp_module and looks_like_cpp_alloc) {
                    const func_ptr_key = @intFromPtr(alloc_info.func_name.ptr);
                    const already_reported = reported_func_ptrs.contains(func_ptr_key);
                    if (!already_reported) {
                        stats.memory_leaks += 1;
                        // P20: Structured candidate evidence
                        var cpp_cand = IssueCandidate.init(ctx.allocator, .leak, 0.5);
                        cpp_cand.func_name = alloc_info.func_name;
                        cpp_cand.addEvidence("C++ internal leak: no free path") catch {};
                        ctx.addIssue(&Issue.init(
                            .memory_leak,
                            "C++ heap allocation never freed (internal leak)",
                            Location.init(alloc_info.func_name),
                            .low,
                            0.5,
                        )) catch {
                            diag.warn("Failed to register C++ leak issue", .{});
                        };
                        diag.warn("MEMORY LEAK [LOW]: C++ allocation never freed in {s}", .{
                            alloc_info.func_name,
                        });
                        reported_func_ptrs.put(func_ptr_key, {}) catch {};
                    }
                }
                diag.debug("LEAK-SKIP: alloc {d} not on danger path (pure internal)", .{alloc_info.inst_id});
                continue;
            }

            // T1.4 C++ Internal Leak Gate: suppress STL/runtime internal allocations
            // in C++ modules. These are managed by the C++ runtime and are NOT real leaks.
            const is_cpp_module = ctx.module_language.language == .cpp or
                ctx.module_language.language == .unknown;
            if (is_cpp_module and isCppInternalLeakPattern(alloc_info.func_name)) {
                stats.cpp_internal_suppressed += 1;
                diag.debug("CPP-LEAK-GATE: suppressed STL internal leak in {s} (C++ module)", .{alloc_info.func_name});
                continue;
            }

            const func_ptr_key = @intFromPtr(alloc_info.func_name.ptr);
            const already_reported = reported_func_ptrs.contains(func_ptr_key);
            if (!already_reported) {
                stats.memory_leaks += 1;
                // P20: Structured candidate evidence
                var gen_cand = IssueCandidate.init(ctx.allocator, .leak, 0.7);
                gen_cand.func_name = alloc_info.func_name;
                gen_cand.alloc_ptr = @as(u64, alloc_info.inst_id);
                gen_cand.inst_addr = @as(u64, alloc_info.inst_id);
                gen_cand.addEvidence("No free path found in reverse BFS analysis") catch {};
                ctx.addIssue(&Issue.init(
                    .memory_leak,
                    "Memory allocated but never freed",
                    Location.init(alloc_info.func_name),
                    .medium,
                    0.7,
                )) catch {
                    diag.warn("Failed to register leak issue", .{});
                };
                diag.warn("MEMORY LEAK [MEDIUM]: Memory allocated but never freed in {s}", .{alloc_info.func_name});
                reported_func_ptrs.put(func_ptr_key, {}) catch {
                    diag.warn("Leak dedup map insert failed", .{});
                };
            }
        }
    }
}
