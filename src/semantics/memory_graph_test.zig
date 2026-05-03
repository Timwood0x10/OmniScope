//! Tests for MemoryGraph module.
//!
//! Extracted from memory_graph.zig to comply with the 1000-line limit.

const std = @import("std");

const MemoryGraph = @import("memory_graph.zig").MemoryGraph;
const SourceKind = @import("memory_graph.zig").SourceKind;
const DangerPathKind = @import("memory_graph.zig").DangerPathKind;

test "memory_graph - basic alloc tracking" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var graph = try MemoryGraph.init(allocator);
    defer graph.deinit();

    const fake_malloc: u64 = 0x1000;
    const fake_ret: u64 = 0x2000;

    const alloc_id = try graph.trackAlloc(fake_malloc, fake_ret, .heap_alloc, .safe, .c);
    try std.testing.expectEqual(@as(u64, 1), alloc_id);

    const node = graph.nodes.get(fake_ret);
    try std.testing.expect(node != null);
    try std.testing.expectEqual(@as(u64, 1), node.?.id);
    try std.testing.expect(!node.?.freed);
    try std.testing.expectEqual(SourceKind.heap_alloc, node.?.source_kind);
}

test "memory_graph - alias tracking" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var graph = try MemoryGraph.init(allocator);
    defer graph.deinit();

    const fake_malloc: u64 = 0x1000;
    const fake_ret1: u64 = 0x2000;
    const fake_ret2: u64 = 0x3000;

    _ = try graph.trackAlloc(fake_malloc, fake_ret1, .heap_alloc, .safe, .c);
    try graph.trackAlias(fake_ret2, fake_ret1);

    const node1 = graph.nodes.get(fake_ret1);
    const node2 = graph.nodes.get(fake_ret2);
    try std.testing.expect(node1 != null);
    try std.testing.expect(node2 != null);
    try std.testing.expectEqual(node1.?.id, node2.?.id);
}

test "memory_graph - double free detection" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var graph = try MemoryGraph.init(allocator);
    defer graph.deinit();

    const fake_malloc: u64 = 0x1000;
    const fake_ret: u64 = 0x2000;
    const fake_free1: u64 = 0x3000;
    const fake_free2: u64 = 0x4000;

    _ = try graph.trackAlloc(fake_malloc, fake_ret, .heap_alloc, .safe, .c);

    const first_free = try graph.trackFree(fake_free1, fake_ret, .c);
    try std.testing.expect(!first_free);

    const second_free = try graph.trackFree(fake_free2, fake_ret, .c);
    try std.testing.expect(second_free);
}

test "memory_graph - alias double free" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var graph = try MemoryGraph.init(allocator);
    defer graph.deinit();

    const fake_malloc: u64 = 0x1000;
    const fake_ret1: u64 = 0x2000;
    const fake_ret2: u64 = 0x3000;
    const fake_free1: u64 = 0x4000;
    const fake_free2: u64 = 0x5000;

    _ = try graph.trackAlloc(fake_malloc, fake_ret1, .heap_alloc, .safe, .c);
    try graph.trackAlias(fake_ret2, fake_ret1);

    _ = try graph.trackFree(fake_free1, fake_ret2, .c);

    const is_double = try graph.trackFree(fake_free2, fake_ret1, .c);
    try std.testing.expect(is_double);
}

test "memory_graph - is_freed" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var graph = try MemoryGraph.init(allocator);
    defer graph.deinit();

    const fake_malloc: u64 = 0x1000;
    const fake_ret: u64 = 0x2000;
    const fake_free: u64 = 0x3000;

    _ = try graph.trackAlloc(fake_malloc, fake_ret, .heap_alloc, .safe, .c);

    try std.testing.expect(!graph.isFreed(fake_ret));

    _ = try graph.trackFree(fake_free, fake_ret, .c);
    try std.testing.expect(graph.isFreed(fake_ret));
}

test "memory_graph - source_kind tracking" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var graph = try MemoryGraph.init(allocator);
    defer graph.deinit();

    const fake_malloc: u64 = 0x1000;
    const fake_ret: u64 = 0x2000;
    const fake_alloca: u64 = 0x3000;

    _ = try graph.trackAlloc(fake_malloc, fake_ret, .heap_alloc, .safe, .c);
    try std.testing.expectEqual(SourceKind.heap_alloc, graph.getSourceKind(fake_ret));

    _ = try graph.trackAlloc(fake_alloca, fake_alloca, .alloca, .safe, .c);
    try std.testing.expectEqual(SourceKind.alloca, graph.getSourceKind(fake_alloca));

    try std.testing.expectEqual(SourceKind.unknown, graph.getSourceKind(0xDEAD));
}

test "memory_graph - func_counter balance" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var graph = try MemoryGraph.init(allocator);
    defer graph.deinit();

    const func: u64 = 0xA000;

    // No ops yet.
    var counter = graph.getFuncCounter(func);
    try std.testing.expectEqual(@as(u32, 0), counter.allocs);
    try std.testing.expectEqual(@as(u32, 0), counter.frees);
    try std.testing.expect(!counter.hasHeapOps());

    // 3 allocs, 1 free.
    graph.recordFuncAlloc(func);
    graph.recordFuncAlloc(func);
    graph.recordFuncAlloc(func);
    graph.recordFuncFree(func);

    counter = graph.getFuncCounter(func);
    try std.testing.expectEqual(@as(u32, 3), counter.allocs);
    try std.testing.expectEqual(@as(u32, 1), counter.frees);
    try std.testing.expectEqual(@as(i64, 2), counter.net());
    try std.testing.expect(counter.hasHeapOps());

    // Balanced: 2 more frees.
    graph.recordFuncFree(func);
    graph.recordFuncFree(func);

    counter = graph.getFuncCounter(func);
    try std.testing.expectEqual(@as(i64, 0), counter.net());
}

test "memory_graph - content_source tracking" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var graph = try MemoryGraph.init(allocator);
    defer graph.deinit();

    const alloca_ptr: u64 = 0x1000;

    // alloca contains a heap pointer.
    graph.recordContentSource(alloca_ptr, .heap_alloc);

    // Direct source of alloca is .alloca.
    _ = try graph.trackAlloc(alloca_ptr, alloca_ptr, .alloca, .safe, .c);
    try std.testing.expectEqual(SourceKind.alloca, graph.getSourceKind(alloca_ptr));

    // Direct source of alloca is .alloca — this doesn't change even though
    // it contains a heap pointer. resolveSourceKind returns direct source first.
    try std.testing.expectEqual(SourceKind.alloca, graph.resolveSourceKind(alloca_ptr));

    // For an untracked pointer that has content source recorded.
    const unknown_ptr: u64 = 0x3000;
    graph.recordContentSource(unknown_ptr, .heap_alloc);
    try std.testing.expectEqual(SourceKind.unknown, graph.getSourceKind(unknown_ptr));
    try std.testing.expectEqual(SourceKind.heap_alloc, graph.resolveSourceSource(unknown_ptr));
}

test "memory_graph - no memory leaks" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked != .ok) @panic("memory leak detected");
    }
    const allocator = gpa.allocator();

    var graph = try MemoryGraph.init(allocator);
    defer graph.deinit();

    var i: u64 = 0;
    while (i < 100) : (i += 1) {
        _ = try graph.trackAlloc(i * 0x1000, i * 0x1000 + 1, .heap_alloc, .safe, .c);
        if (i > 0) {
            try graph.trackAlias(i * 0x1000 + 1, (i - 1) * 0x1000 + 1);
        }
        graph.recordFuncAlloc(0xA000);
        graph.recordContentSource(i * 0x1000, .alloca);
    }

    i = 0;
    while (i < 50) : (i += 1) {
        _ = try graph.trackFree(i * 0x1000 + 2, i * 0x1000 + 1, .c);
        graph.recordFuncFree(0xA000);
    }
}

test "memory_graph - trackCallArg basic" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked != .ok) @panic("memory leak detected");
    }
    const allocator = gpa.allocator();

    var graph = try MemoryGraph.init(allocator);
    defer graph.deinit();

    // Track a call_arg: ptr 0x1000 passed as arg 0 to "malloc"
    try graph.trackCallArg(0x2000, "malloc", 0x1000, 0);

    // Verify call_args list has 1 entry
    try std.testing.expectEqual(@as(usize, 1), graph.call_args.items.len);

    const edge = graph.call_args.items[0];
    try std.testing.expectEqual(@as(u64, 0x2000), edge.caller_inst);
    try std.testing.expectEqualStrings("malloc", edge.callee_name);
    try std.testing.expectEqual(@as(u64, 0x1000), edge.arg_ptr);
    try std.testing.expectEqual(@as(u32, 0), edge.arg_index);

    // Query by ptr should find this edge
    const args_for_ptr = graph.getCallArgsForPtr(0x1000);
    try std.testing.expectEqual(@as(usize, 1), args_for_ptr.len);
}

test "memory_graph - trackCallRet basic" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked != .ok) @panic("memory leak detected");
    }
    const allocator = gpa.allocator();

    var graph = try MemoryGraph.init(allocator);
    defer graph.deinit();

    // Track a call_ret: ptr 0x2000 returned from "malloc"
    try graph.trackCallRet(0x3000, "malloc", 0x2000);

    // Verify call_rets list has 1 entry
    try std.testing.expectEqual(@as(usize, 1), graph.call_rets.items.len);

    const edge = graph.call_rets.items[0];
    try std.testing.expectEqual(@as(u64, 0x3000), edge.caller_inst);
    try std.testing.expectEqualStrings("malloc", edge.callee_name);
    try std.testing.expectEqual(@as(u64, 0x2000), edge.ret_ptr);

    // Query by callee should find this edge
    const rets_from_callee = graph.getCallRetsFromCallee("malloc");
    try std.testing.expectEqual(@as(usize, 1), rets_from_callee.len);
}

test "memory_graph - isPassedAsArg and isReturnedFromCall" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked != .ok) @panic("memory leak detected");
    }
    const allocator = gpa.allocator();

    var graph = try MemoryGraph.init(allocator);
    defer graph.deinit();

    // Initially nothing is passed or returned
    try std.testing.expect(!graph.isPassedAsArg(0x1000));
    try std.testing.expect(!graph.isReturnedFromCall(0x2000));

    // Add a call_arg
    try graph.trackCallArg(0x5000, "free", 0x1000, 0);
    try std.testing.expect(graph.isPassedAsArg(0x1000));
    try std.testing.expect(!graph.isReturnedFromCall(0x1000));

    // Add a call_ret
    try graph.trackCallRet(0x6000, "malloc", 0x2000);
    try std.testing.expect(graph.isReturnedFromCall(0x2000));
    try std.testing.expect(!graph.isPassedAsArg(0x2000));
}

test "memory_graph - multiple call edges for same pointer" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked != .ok) @panic("memory leak detected");
    }
    const allocator = gpa.allocator();

    var graph = try MemoryGraph.init(allocator);
    defer graph.deinit();

    // Same ptr passed to different functions
    try graph.trackCallArg(0x1000, "free", 0x5000, 0);
    try graph.trackCallArg(0x2000, "fclose", 0x5000, 0);
    try graph.trackCallArg(0x3000, "pthread_create", 0x5000, 2);

    // Should find all 3 edges
    const args = graph.getCallArgsForPtr(0x5000);
    try std.testing.expectEqual(@as(usize, 3), args.len);
}

test "memory_graph - call edges coexist with alloc/free tracking" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked != .ok) @panic("memory leak detected");
    }
    const allocator = gpa.allocator();

    var graph = try MemoryGraph.init(allocator);
    defer graph.deinit();

    // Track allocation
    _ = try graph.trackAlloc(0x1000, 0x1001, .heap_alloc, .safe, .c);

    // Track call_arg with the allocated pointer
    try graph.trackCallArg(0x2000, "process_data", 0x1001, 0);

    // Track free
    _ = try graph.trackFree(0x3000, 0x1001, .c);

    // All data should coexist
    try std.testing.expect(graph.nodes.contains(0x1001));
    try std.testing.expectEqual(@as(usize, 1), graph.call_args.items.len);
    const node = graph.nodes.get(0x1001).?;
    try std.testing.expect(node.freed);
}

test "memory_graph - isLeaked cross-function propagation" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked != .ok) @panic("memory leak detected");
    }
    const allocator = gpa.allocator();

    var graph = try MemoryGraph.init(allocator);
    defer graph.deinit();

    _ = try graph.trackAlloc(0x1000, 0xA001, .heap_alloc, .safe, .c);

    try std.testing.expect(!graph.isLeaked(0xA001));
    try std.testing.expect(!graph.isLeaked(0x9999));

    try graph.trackCallArg(0x2000, "sink", 0xA001, 0);

    try std.testing.expect(graph.isLeaked(0xA001));

    try graph.trackCallRet(0x2000, "sink", 0xB001);

    try std.testing.expect(!graph.isLeaked(0xA001));

    _ = try graph.trackFree(0x3000, 0xA001, .c);
    try std.testing.expect(!graph.isLeaked(0xA001));
}

test "memory_graph - isDoubleFreed alias closure + call chain" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked != .ok) @panic("memory leak detected");
    }
    const allocator = gpa.allocator();

    var graph = try MemoryGraph.init(allocator);
    defer graph.deinit();

    _ = try graph.trackAlloc(0x1000, 0xA001, .heap_alloc, .safe, .c);
    try std.testing.expect(!graph.isDoubleFreed(0xA001));

    _ = try graph.trackFree(0x3000, 0xA001, .c);
    try std.testing.expect(graph.isDoubleFreed(0xA001));

    var graph2 = try MemoryGraph.init(allocator);
    defer graph2.deinit();

    _ = try graph2.trackAlloc(0x1000, 0xA002, .heap_alloc, .safe, .c);
    try graph2.trackAlias(0xB002, 0xA002);
    _ = try graph2.trackFree(0x3000, 0xB002, .c);
    try std.testing.expect(graph2.isDoubleFreed(0xA002));

    var graph3 = try MemoryGraph.init(allocator);
    defer graph3.deinit();

    _ = try graph3.trackAlloc(0x1000, 0xA003, .heap_alloc, .safe, .c);
    try graph3.trackCallArg(0x2000, "free_it", 0xA003, 0);
    try graph3.trackCallRet(0x2000, "free_it", 0xB003);
    try graph3.trackAlias(0xB003, 0xA003);
    _ = try graph3.trackFree(0x4000, 0xB003, .c);
    try std.testing.expect(graph3.isDoubleFreed(0xA003));
}

test "memory_graph - isOnDangerPath pure internal returns none" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked != .ok) @panic("memory leak detected");
    }
    const allocator = gpa.allocator();

    var graph = try MemoryGraph.init(allocator);
    defer graph.deinit();

    _ = try graph.trackAlloc(0x1000, 0xA001, .heap_alloc, .safe, .c);
    _ = try graph.trackFree(0x3000, 0xA001, .c);

    var visited = std.AutoHashMap(u64, void).init(allocator);
    defer visited.deinit();
    const boundaries = [_]MemoryGraph.DangerSurface{};
    try std.testing.expectEqual(DangerPathKind.none, graph.isOnDangerPath(0xA001, &boundaries, &visited));
}

test "memory_graph - isOnDangerPath cross-lang lifecycle" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked != .ok) @panic("memory leak detected");
    }
    const allocator = gpa.allocator();

    var graph = try MemoryGraph.init(allocator);
    defer graph.deinit();

    _ = try graph.trackAlloc(0x1000, 0xA001, .heap_alloc, .safe, .rust);
    _ = try graph.trackFree(0x3000, 0xA001, .c);

    var visited = std.AutoHashMap(u64, void).init(allocator);
    defer visited.deinit();
    const boundaries = [_]MemoryGraph.DangerSurface{};
    try std.testing.expectEqual(DangerPathKind.cross_lang_lifecycle, graph.isOnDangerPath(0xA001, &boundaries, &visited));
}

test "memory_graph - isOnDangerPath FFI arg flow" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked != .ok) @panic("memory leak detected");
    }
    const allocator = gpa.allocator();

    var graph = try MemoryGraph.init(allocator);
    defer graph.deinit();

    _ = try graph.trackAlloc(0x1000, 0xA001, .heap_alloc, .safe, .c);
    try graph.trackCallArg(0x2000, "C.malloc", 0xA001, 0);

    var visited = std.AutoHashMap(u64, void).init(allocator);
    defer visited.deinit();
    const boundaries = [_]MemoryGraph.DangerSurface{
        .{ .callee_name = "C.malloc", .is_ffi_boundary = true },
    };
    try std.testing.expectEqual(DangerPathKind.ffi_arg, graph.isOnDangerPath(0xA001, &boundaries, &visited));
}

test "memory_graph - isOnDangerPath unsafe zone alloc" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked != .ok) @panic("memory leak detected");
    }
    const allocator = gpa.allocator();

    var graph = try MemoryGraph.init(allocator);
    defer graph.deinit();

    _ = try graph.trackAlloc(0x1000, 0xA001, .heap_alloc, .unsafe, .rust);

    var visited = std.AutoHashMap(u64, void).init(allocator);
    defer visited.deinit();
    const boundaries = [_]MemoryGraph.DangerSurface{};
    try std.testing.expectEqual(DangerPathKind.unsafe_alloc, graph.isOnDangerPath(0xA001, &boundaries, &visited));
}

test "memory_graph - resolveContentSource multi-level fallback" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked != .ok) @panic("memory leak detected");
    }
    const allocator = gpa.allocator();

    var graph = try MemoryGraph.init(allocator);
    defer graph.deinit();

    _ = try graph.trackAlloc(0x1000, 0xA001, .heap_alloc, .safe, .c);

    try std.testing.expectEqual(SourceKind.heap_alloc, graph.resolveContentSource(0xA001));

    graph.recordContentSource(0xB001, .alloca);
    try std.testing.expectEqual(SourceKind.alloca, graph.getContentSource(0xB001));
    try std.testing.expectEqual(SourceKind.alloca, graph.resolveContentSource(0xB001));

    try std.testing.expectEqual(SourceKind.unknown, graph.getContentSource(0xC001));
    try std.testing.expectEqual(SourceKind.unknown, graph.resolveContentSource(0xC001));

    _ = try graph.trackCallRet(0x2000, "malloc_wrapper", 0xD001);
    try std.testing.expectEqual(SourceKind.call_result, graph.resolveContentSource(0xD001));
}

test "memory_graph - isOnDangerPath alias propagation" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked != .ok) @panic("memory leak detected");
    }
    const allocator = gpa.allocator();

    var graph = try MemoryGraph.init(allocator);
    defer graph.deinit();

    _ = try graph.trackAlloc(0x1000, 0xA001, .heap_alloc, .safe, .c);
    try graph.trackAlias(0xB001, 0xA001);
    try graph.trackCallArg(0x2000, "ffi_callback", 0xB001, 0);

    var visited = std.AutoHashMap(u64, void).init(allocator);
    defer visited.deinit();
    const boundaries = [_]MemoryGraph.DangerSurface{
        .{ .callee_name = "ffi_callback", .is_ffi_boundary = true },
    };
    // 0xA001 itself doesn't have call_arg, but its alias 0xB001 does
    try std.testing.expectEqual(DangerPathKind.ffi_arg, graph.isOnDangerPath(0xA001, &boundaries, &visited));
}

test "memory_graph - isOnDangerPath cycle detection A<->B no infinite loop" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked != .ok) @panic("memory leak detected");
    }
    const allocator = gpa.allocator();

    var graph = try MemoryGraph.init(allocator);
    defer graph.deinit();

    _ = try graph.trackAlloc(0x1000, 0xA001, .heap_alloc, .safe, .c);
    _ = try graph.trackAlloc(0x1001, 0xB001, .heap_alloc, .safe, .c);

    try graph.trackAlias(0xA001, 0xB001);
    try graph.trackAlias(0xB001, 0xA001);

    var visited = std.AutoHashMap(u64, void).init(allocator);
    defer visited.deinit();
    const boundaries = [_]MemoryGraph.DangerSurface{};

    const result = graph.isOnDangerPath(0xA001, &boundaries, &visited);
    try std.testing.expectEqual(DangerPathKind.none, result);
}
