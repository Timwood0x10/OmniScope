const std = @import("std");
const contract_graph = @import("contract_graph_builder.zig");
pub const ResourceInstance = contract_graph.ResourceInstance;
pub const ContractEdge = contract_graph.ContractEdge;
pub const ResourceContractGraph = contract_graph.ResourceContractGraph;
const contract = @import("../../semantics/resource/contract.zig");
pub const PointerContract = contract.PointerContract;
const effect_mod = @import("../../semantics/resource/effect.zig");
const Effect = effect_mod.Effect;

pub const PathClassification = enum(u8) {
    released_path,
    escaped_path,
    leak_path,
    unknown_path,
    cleanup_path,
};

pub const LeakCandidate = struct {
    instance_id: u32,
    classification: PathClassification,
    leaky_paths: u32,
    total_paths: u32,
    confidence: f32,
    has_cleanup_alternative: bool,

    pub fn format(
        self: LeakCandidate,
        comptime _: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        try writer.print("LeakCandidate(inst={}, class={}, leaky={}/{}, conf={d:.2}, cleanup={})", .{
            self.instance_id,
            @tagName(self.classification),
            self.leaky_paths,
            self.total_paths,
            self.confidence,
            self.has_cleanup_alternative,
        });
    }
};

const CONF_ALL_LEAKING: f32 = 0.90;
const CONF_SOME_LEAKING: f32 = 0.65;
const CONF_NONE_LEAKING: f32 = 0.0;

const CLEANUP_PATTERNS = [_][]const u8{
    "_cleanup",
    "_fail",
    "errdefer",
    "defer_",
    "__cxa_begin_catch",
    "goto ",
    "__attribute__((cleanup",
    "RAII",
    "destructor",
    "~",
    "Drop(",
    "drop(",
};

pub const PathAnalyzer = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) PathAnalyzer {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *PathAnalyzer) void {
        _ = self;
    }

    pub fn analyzeInstance(self: *PathAnalyzer, inst: *ResourceInstance) ?LeakCandidate {
        _ = self;
        const edges = inst.edges.items;
        if (edges.len == 0) return null;

        var total_paths: u32 = 0;
        var release_count: u32 = 0;
        var escape_count: u32 = 0;
        var has_cleanup: bool = false;

        for (edges) |edge| {
            total_paths += 1;
            switch (edge.effect) {
                .releases => release_count += 1,
                .conditional_release => release_count += 1,
                .returns_owned, .transfers, .consumes_arg => escape_count += 1,
                .stores_arg_to_owner, .stores_arg_to_global => escape_count += 1,
                .initializes_out_param => escape_count += 1,
                .escapes_to_callback => escape_count += 1,
                else => {},
            }
            if (isCleanupEdge(&edge)) has_cleanup = true;
        }

        const classification: PathClassification = blk: {
            if (release_count > 0) break :blk .released_path;
            if (escape_count > 0) break :blk .escaped_path;
            if (has_cleanup) break :blk .cleanup_path;
            if (total_paths > 0) break :blk .leak_path;
            break :blk .unknown_path;
        };

        const leaky_paths: u32 = switch (classification) {
            .released_path, .escaped_path, .cleanup_path => 0,
            .leak_path => total_paths,
            .unknown_path => total_paths,
        };

        const confidence: f32 = if (classification == .leak_path and leaky_paths == total_paths)
            CONF_ALL_LEAKING
        else if (classification == .leak_path)
            CONF_SOME_LEAKING
        else
            CONF_NONE_LEAKING;

        return LeakCandidate{
            .instance_id = inst.id,
            .classification = classification,
            .leaky_paths = leaky_paths,
            .total_paths = total_paths,
            .confidence = confidence,
            .has_cleanup_alternative = has_cleanup,
        };
    }

    pub fn analyzeAll(self: *PathAnalyzer, graph: *ResourceContractGraph) ![]LeakCandidate {
        var candidates = std.ArrayList(LeakCandidate).init(self.allocator);
        errdefer candidates.deinit();
        var it = graph.instances.iterator();
        while (it.next()) |entry| {
            if (self.analyzeInstance(&entry.value_ptr)) |candidate| {
                if (candidate.classification == .leak_path or
                    candidate.classification == .unknown_path)
                {
                    try candidates.append(candidate);
                }
            }
        }
        return candidates.toOwnedSlice();
    }
};

fn isCleanupEdge(edge: *const ContractEdge) bool {
    const callee = edge.callee_name orelse return false;
    for (CLEANUP_PATTERNS) |pat| {
        if (std.mem.indexOf(u8, callee, pat) != null) return true;
    }
    return false;
}
