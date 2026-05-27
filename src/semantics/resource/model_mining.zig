//! P10: Project Semantic Model Mining — Auto-discovers allocator/deallocator pairs.
//!
//! Mines allocator/deallocator function pairs from project IR without manual
//! whitelist. Uses naming convention heuristics, pattern scoring, and pairing
//! rules to suggest candidate resource management functions.

const std = @import("std");
const func_summary = @import("function_summary.zig");
pub const SummaryStore = func_summary.SummaryStore;
pub const ResourceFunctionSummary = func_summary.ResourceFunctionSummary;
pub const Effect = @import("effect.zig").Effect;

/// A mined allocator/deallocator pair discovered from project IR.
pub const MinedPair = struct {
    /// Suspected allocator function name.
    allocator_name: []const u8,
    /// Suspected deallocator function name.
    deallocator_name: []const u8,
    /// Confidence [0.0, 1.0] in this pair being real.
    confidence: f32,
    /// Evidence items explaining why this pair was suggested.
    evidence: std.ArrayList([]const u8),
    /// Inferred family name (if determinable).
    inferred_family: ?[]const u8,

    pub fn init(alloc_name: []const u8, dealloc_name: []const u8, allocator: std.mem.Allocator) MinedPair {
        return .{
            .allocator_name = alloc_name,
            .deallocator_name = dealloc_name,
            .confidence = 0.5,
            .evidence = std.ArrayList([]const u8).init(allocator),
            .inferred_family = null,
        };
    }

    pub fn deinit(self: *MinedPair) void {
        self.evidence.deinit();
    }
};

/// Project model mining result.
pub const MinedModel = struct {
    pairs: std.ArrayList(MinedPair),
    unknown_functions: std.ArrayList([]const u8),

    pub fn init(allocator: std.mem.Allocator) MinedModel {
        return .{
            .pairs = std.ArrayList(MinedPair).init(allocator),
            .unknown_functions = std.ArrayList([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *MinedModel) void {
        for (self.pairs.items) |*pair| {
            pair.deinit();
        }
        self.pairs.deinit();
        self.unknown_functions.deinit();
    }
};

/// Mines allocator/deallocator pairs from a set of function names found in the project.
pub const ModelMiner = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) ModelMiner {
        return .{ .allocator = allocator };
    }

    /// Run mining on a list of function names found in the project.
    /// Returns a MinedModel with discovered pairs.
    /// Caller owns returned MinedModel and must call deinit() when done.
    pub fn mine(self: *ModelMiner, function_names: [][]const u8) !MinedModel {
        var model = MinedModel.init(self.allocator);
        errdefer model.deinit();

        // P10-2: Find candidate allocators (name contains alloc/new/create/open/init)
        const CandidateEntry = struct { []const u8, f32 };
        var candidates_alloc = std.ArrayList(CandidateEntry).init(self.allocator);
        defer candidates_alloc.deinit();
        for (function_names) |name| {
            const score = scoreAsAllocator(name);
            if (score > 0.3) {
                try candidates_alloc.append(.{ name, score });
            }
        }

        // P10-3: Find candidate deallocators (name contains free/delete/destroy/close/deinit/release)
        var candidates_dealloc = std.ArrayList(CandidateEntry).init(self.allocator);
        defer candidates_dealloc.deinit();
        for (function_names) |name| {
            const score = scoreAsDeallocator(name);
            if (score > 0.3) {
                try candidates_dealloc.append(.{ name, score });
            }
        }

        // P10-4: Pair allocators with deallocators by naming convention
        for (candidates_alloc.items) |alloc_entry| {
            for (candidates_dealloc.items) |dealloc_entry| {
                if (try self.arePaired(alloc_entry[0], dealloc_entry[0])) {
                    var pair = MinedPair.init(alloc_entry[0], dealloc_entry[0], self.allocator);
                    pair.confidence = (alloc_entry[1] + dealloc_entry[1]) / 2.0;
                    try pair.evidence.append("Naming convention match: alloc+free pattern");
                    pair.inferred_family = inferFamilyFromNames(alloc_entry[0], dealloc_entry[0]);
                    try model.pairs.append(pair);
                }
            }
        }

        // Collect unknown functions (neither alloc nor dealloc pattern matched)
        for (function_names) |name| {
            if (scoreAsAllocator(name) <= 0.3 and scoreAsDeallocator(name) <= 0.3) {
                try model.unknown_functions.append(name);
            }
        }

        return model;
    }

    /// Score how likely a function is an allocator [0.0, 1.0].
    pub fn scoreAsAllocator(name: []const u8) f32 {
        const patterns = [_]struct { []const u8, f32 }{
            .{ "malloc", 1.0 },
            .{ "calloc", 1.0 },
            .{ "realloc", 0.95 },
            .{ "alloc", 0.85 },
            .{ "allocate", 0.85 },
            .{ "_new", 0.80 },
            .{ "create", 0.75 },
            .{ "open", 0.70 },
            .{ "init", 0.40 },
            .{ "new", 0.60 },
            .{ "dup", 0.55 },
            .{ "acquire", 0.70 },
            .{ "obtain", 0.65 },
            .{ "PyObject_New", 0.95 },
            .{ "PyMem_Malloc", 0.95 },
            .{ "g_malloc", 0.85 },
            .{ "g_slice_alloc", 0.80 },
        };
        for (patterns) |entry| {
            if (indexOfIC(name, entry[0]) != null) return entry[1];
        }
        return 0.0;
    }

    /// Score how likely a function is a deallocator [0.0, 1.0].
    pub fn scoreAsDeallocator(name: []const u8) f32 {
        const patterns = [_]struct { []const u8, f32 }{
            .{ "free", 1.0 },
            .{ "dealloc", 0.95 },
            .{ "destroy", 0.90 },
            .{ "delete", 0.88 },
            .{ "close", 0.75 },
            .{ "release", 0.70 },
            .{ "dispose", 0.85 },
            .{ "finalize", 0.75 },
            .{ "cleanup", 0.65 },
            .{ "deinit", 0.72 },
            .{ "PyObject_Del", 0.95 },
            .{ "PyMem_Free", 0.95 },
            .{ "g_free", 0.85 },
            .{ "g_slice_free", 0.80 },
        };
        for (patterns) |entry| {
            if (indexOfIC(name, entry[0]) != null) return entry[1];
        }
        return 0.0;
    }

    /// Check if two functions form an alloc/free pair by naming convention.
    fn arePaired(self: *ModelMiner, alloc_name: []const u8, dealloc_name: []const u8) !bool {
        _ = self;
        // Pattern 1: foo_alloc / foo_free
        if (hasCommonPrefix(alloc_name, dealloc_name)) return true;
        // Pattern 2: FooCreate / FooDestroy or FooOpen / FooClose
        if (hasBaseNameMatch(alloc_name, dealloc_name, &[_][2][]const u8{
            .{ "Create", "Destroy" },
            .{ "Open", "Close" },
        })) return true;
        // Pattern 3: foo_new / foo_delete
        if (hasBaseNameMatch(alloc_name, dealloc_name, &[_][2][]const u8{
            .{ "new", "delete" },
            .{ "New", "Delete" },
        })) return true;
        return false;
    }
};

// ============================================================================
// Helpers — case-insensitive string matching utilities
// ============================================================================

fn indexOfIC(haystack: []const u8, needle: []const u8) ?usize {
    if (needle.len > haystack.len) return null;
    var i: usize = 0;
    while (i <= haystack.len - needle.len) : (i += 1) {
        var match = true;
        for (needle, 0..) |nc, j| {
            const hc = haystack[i + j];
            const hlc = if (hc >= 'A' and hc <= 'Z') hc + 32 else hc;
            const nlc = if (nc >= 'A' and nc <= 'Z') nc + 32 else nc;
            if (hlc != nlc) {
                match = false;
                break;
            }
        }
        if (match) return i;
    }
    return null;
}

fn hasCommonPrefix(a: []const u8, b: []const u8) bool {
    const min_len = @min(a.len, b.len);
    if (min_len < 4) return false;
    return std.mem.eql(u8, a[0..min_len], b[0..min_len]);
}

fn hasBaseNameMatch(a: []const u8, b: []const u8, pairs: *const [][2][]const u8) bool {
    for (pairs.*) |pair| {
        const pfx_a = pair[0];
        const pfx_b = pair[1];
        if ((endsWithIC(a, pfx_a) or indexOfIC(a, pfx_a) != null) and
            (endsWithIC(b, pfx_b) or indexOfIC(b, pfx_b) != null))
        {
            return true;
        }
    }
    return false;
}

fn endsWithIC(haystack: []const u8, needle: []const u8) bool {
    if (needle.len > haystack.len) return false;
    const start = haystack.len - needle.len;
    for (needle, 0..) |nc, i| {
        const hc = haystack[start + i];
        const hlc = if (hc >= 'A' and hc <= 'Z') hc + 32 else hc;
        const nlc = if (nc >= 'A' and nc <= 'Z') nc + 32 else nc;
        if (hlc != nlc) return false;
    }
    return true;
}

fn inferFamilyFromNames(alloc_name: []const u8, dealloc_name: []const u8) ?[]const u8 {
    if (indexOfIC(alloc_name, "Py") != null) return "python";
    if (indexOfIC(alloc_name, "g_") != null) return "glib";
    if (indexOfIC(alloc_name, "objc") != null) return "objective_c";
    if (endsWithIC(dealloc_name, "Free") and indexOfIC(alloc_name, "Alloc") != null) return "custom";
    return null;
}
