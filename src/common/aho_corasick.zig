//! Aho-Corasick Multi-Pattern Matching Automaton
//!
//! Efficient O(n + m + z) string matching algorithm for multiple patterns,
//! where n is text length, m is total pattern length, and z is number of matches.
//!
//! Runtime-allocating implementation designed for integration with PatternRegistry.
//!
//! ## Matching Modes
//!
//! - **contains**: Find any occurrence of pattern within text (default behavior).
//!   Returns the first match found scanning left-to-right.
//! - **prefix**: Match only if pattern appears at the start of text.
//!   Useful for checking if text begins with specific patterns.
//! - **exact**: Match only if text exactly equals pattern.
//!   Useful for exact string comparison against multiple patterns.
//!
//! ## Usage
//! ```zig
//! var ac = AhoCorasick.init(allocator);
//! defer ac.deinit();
//!
//! try ac.addPattern("strcpy", 0);
//! try ac.addPattern("system", 1);
//! ac.build() catch unreachable;
//!
//! if (ac.search("call to strcpy here")) |match| {
//!     std.log.info("matched pattern id={d} at pos={d}", .{ match.pattern_id, match.start });
//! }
//! ```

const std = @import("std");
const log = @import("log.zig");
const Allocator = std.mem.Allocator;
const HashMap = std.AutoHashMap;
const ArrayList = std.ArrayList;

/// Result of a pattern match within text.
pub const MatchResult = struct {
    /// User-provided pattern ID
    pattern_id: usize,
    /// Start byte offset in text (inclusive)
    start: usize,
    /// End byte offset in text (exclusive)
    end: usize,
};

/// Matching mode for search operations.
pub const MatchMode = enum {
    /// Find any occurrence of pattern within text (default Aho-Corasick behavior)
    contains,
    /// Match only if pattern appears at the start of text
    prefix,
    /// Match only if text exactly equals pattern
    exact,
};

/// Runtime-allocating Aho-Corasick multi-pattern matching automaton.
///
/// Provides efficient multi-pattern string matching in O(n + m + z) time.
/// Uses dynamic memory allocation for flexible pattern set sizes.
pub const AhoCorasick = struct {
    const Self = @This();

    /// Maximum patterns stored per node via output links.
    const MAX_OUTPUT_PER_NODE = 16;

    /// Trie node with children stored as a hash map for memory efficiency.
    const Node = struct {
        /// Sparse children map: byte -> child state index
        children: HashMap(u8, usize),
        /// Failure link for Aho-Corasick automaton
        failure: usize = 0,
        /// List of pattern IDs that end at this node (via output chain)
        output: [MAX_OUTPUT_PER_NODE]usize = undefined,
        /// Number of valid entries in output
        output_len: usize = 0,
    };

    /// All nodes in the automaton (index 0 is root)
    nodes: ArrayList(Node),
    /// Total number of patterns added
    pattern_count: usize = 0,
    /// Whether build() has been called
    built: bool = false,
    /// Allocator for all dynamic memory
    allocator: Allocator,

    /// Initialize a new empty Aho-Corasick automaton.
    pub fn init(allocator: Allocator) Self {
        return Self{
            .nodes = ArrayList(Node).initCapacity(allocator, 64) catch unreachable,
            .allocator = allocator,
        };
    }

    /// Free all resources owned by this automaton.
    pub fn deinit(self: *Self) void {
        for (self.nodes.items) |*node| {
            node.children.deinit();
        }
        self.nodes.deinit(self.allocator);
    }

    /// Add a pattern with a user-provided ID. Must be called before build().
    ///
    /// Parameters:
    ///   - pattern: The byte string pattern to match
    ///   - id: User-provided identifier for this pattern
    ///
    /// Returns error.OutOfMemory if allocation fails.
    pub fn addPattern(self: *Self, pattern: []const u8, id: usize) !void {
        if (self.built) {
            log.err("AhoCorasick: cannot add pattern after build()", .{});
            return;
        }
        if (pattern.len == 0) return;

        // Lazy-init root node
        if (self.nodes.items.len == 0) {
            try self.nodes.append(self.allocator, Node{
                .children = HashMap(u8, usize).init(self.allocator),
            });
        }

        // Walk/insert trie
        var current: usize = 0;
        for (pattern) |ch| {
            const entry = try self.nodes.items[current].children.getOrPut(ch);
            if (!entry.found_existing) {
                // Create new node
                const new_idx = self.nodes.items.len;
                try self.nodes.append(self.allocator, Node{
                    .children = HashMap(u8, usize).init(self.allocator),
                });
                entry.value_ptr.* = new_idx;
            }
            current = entry.value_ptr.*;
        }

        // Record pattern at terminal node
        const node = &self.nodes.items[current];
        if (node.output_len < MAX_OUTPUT_PER_NODE) {
            node.output[node.output_len] = id;
            node.output_len += 1;
        }

        self.pattern_count += 1;
    }

    /// Build failure links and output chains. Must be called after all patterns are added.
    ///
    /// Constructs the Aho-Corasick automaton using BFS to compute:
    /// - Failure links: longest proper suffix that is also a trie node
    /// - Output chains: collect all pattern IDs reachable via failure links
    pub fn build(self: *Self) !void {
        if (self.built) return;
        if (self.nodes.items.len == 0) return;

        // BFS queue for failure link computation
        var queue = ArrayList(usize).initCapacity(self.allocator, self.nodes.items.len) catch
            return error.OutOfMemory;
        defer queue.deinit(self.allocator);

        // Initialize root: missing edges loop to root (state 0)
        var root_children = &self.nodes.items[0].children;
        var it = root_children.iterator();
        while (it.next()) |entry| {
            try queue.append(self.allocator, entry.value_ptr.*);
            self.nodes.items[entry.value_ptr.*].failure = 0;
        }

        // BFS to compute failure links
        var head: usize = 0;
        while (head < queue.items.len) {
            const u = queue.items[head];
            head += 1;

            // Get the byte that led to node u
            const parent_failure = self.nodes.items[u].failure;

            var child_it = self.nodes.items[u].children.iterator();
            while (child_it.next()) |entry| {
                const ch = entry.key_ptr.*;
                const v = entry.value_ptr.*;

                // Compute failure link for v
                var f = parent_failure;
                while (true) {
                    if (self.nodes.items[f].children.get(ch)) |next| {
                        self.nodes.items[v].failure = next;
                        break;
                    }
                    if (f == 0) {
                        self.nodes.items[v].failure = 0;
                        break;
                    }
                    f = self.nodes.items[f].failure;
                }

                // Prevent self-loops
                if (self.nodes.items[v].failure == v) {
                    self.nodes.items[v].failure = 0;
                }

                // Collect output from failure chain into this node
                const fail_node = &self.nodes.items[self.nodes.items[v].failure];
                var i: usize = 0;
                while (i < fail_node.output_len) : (i += 1) {
                    const node = &self.nodes.items[v];
                    if (node.output_len < MAX_OUTPUT_PER_NODE) {
                        node.output[node.output_len] = fail_node.output[i];
                        node.output_len += 1;
                    }
                }

                try queue.append(self.allocator, v);
            }
        }

        self.built = true;
    }

    /// Follow failure links until finding a valid transition for byte `ch`.
    inline fn nextState(self: *const Self, state: usize, ch: u8) usize {
        var s = state;
        while (true) {
            if (self.nodes.items[s].children.get(ch)) |next| {
                return next;
            }
            if (s == 0) return 0;
            s = self.nodes.items[s].failure;
        }
    }

    /// Search for the first matching pattern in text (contains mode).
    ///
    /// Returns the first MatchResult found, scanning left-to-right.
    /// Returns null if no pattern matches.
    pub fn search(self: *const Self, text: []const u8) ?MatchResult {
        return self.searchWithMode(text, .contains);
    }

    /// Search for the first matching pattern with specified match mode.
    pub fn searchWithMode(self: *const Self, text: []const u8, mode: MatchMode) ?MatchResult {
        if (!self.built) {
            log.err("AhoCorasick: search called before build()", .{});
            return null;
        }
        if (self.nodes.items.len == 0) return null;

        var state: usize = 0;
        for (text, 0..) |ch, pos| {
            state = self.nextState(state, ch);

            // Check for matches at current state
            const node = &self.nodes.items[state];
            if (node.output_len > 0) {
                const pattern_end = pos + 1;

                // Apply match mode filter
                switch (mode) {
                    .contains => {
                        return MatchResult{
                            .pattern_id = node.output[0],
                            .start = pattern_end - self.getPatternLen(node.output[0]),
                            .end = pattern_end,
                        };
                    },
                    .prefix => {
                        // Only match if pattern starts at position 0
                        for (0..node.output_len) |i| {
                            const pid = node.output[i];
                            const plen = self.getPatternLen(pid);
                            if (pattern_end >= plen and pattern_end - plen == 0) {
                                return MatchResult{
                                    .pattern_id = pid,
                                    .start = 0,
                                    .end = pattern_end,
                                };
                            }
                        }
                    },
                    .exact => {
                        // Only match if entire text is consumed and pattern covers full text
                        if (pos == text.len - 1) {
                            for (0..node.output_len) |i| {
                                const pid = node.output[i];
                                const plen = self.getPatternLen(pid);
                                if (plen == text.len) {
                                    return MatchResult{
                                        .pattern_id = pid,
                                        .start = 0,
                                        .end = text.len,
                                    };
                                }
                            }
                        }
                    },
                }
            }
        }

        return null;
    }

    /// Find all matching patterns in text (contains mode).
    ///
    /// Appends MatchResult entries to `results` for every match found.
    /// Results are in text-position order; multiple patterns may match at the same position.
    pub fn findAll(self: *const Self, text: []const u8, results: *ArrayList(MatchResult)) !void {
        try self.findAllWithMode(text, results, .contains);
    }

    /// Find all matching patterns with specified match mode.
    pub fn findAllWithMode(self: *const Self, text: []const u8, results: *ArrayList(MatchResult), mode: MatchMode) !void {
        if (!self.built) {
            log.err("AhoCorasick: findAll called before build()", .{});
            return;
        }
        if (self.nodes.items.len == 0) return;

        var state: usize = 0;
        for (text, 0..) |ch, pos| {
            state = self.nextState(state, ch);

            const node = &self.nodes.items[state];
            if (node.output_len > 0) {
                const pattern_end = pos + 1;

                switch (mode) {
                    .contains => {
                        for (0..node.output_len) |i| {
                            const pid = node.output[i];
                            const plen = self.getPatternLen(pid);
                            try results.append(self.allocator, MatchResult{
                                .pattern_id = pid,
                                .start = pattern_end - plen,
                                .end = pattern_end,
                            });
                        }
                    },
                    .prefix => {
                        for (0..node.output_len) |i| {
                            const pid = node.output[i];
                            const plen = self.getPatternLen(pid);
                            if (pattern_end >= plen and pattern_end - plen == 0) {
                                try results.append(self.allocator, MatchResult{
                                    .pattern_id = pid,
                                    .start = 0,
                                    .end = pattern_end,
                                });
                            }
                        }
                    },
                    .exact => {
                        if (pos == text.len - 1) {
                            for (0..node.output_len) |i| {
                                const pid = node.output[i];
                                const plen = self.getPatternLen(pid);
                                if (plen == text.len) {
                                    try results.append(self.allocator, MatchResult{
                                        .pattern_id = pid,
                                        .start = 0,
                                        .end = text.len,
                                    });
                                }
                            }
                        }
                    },
                }
            }
        }
    }

    /// Check if text contains any of the registered patterns.
    pub fn containsAny(self: *const Self, text: []const u8) bool {
        return self.search(text) != null;
    }

    /// Check if text starts with any of the registered patterns.
    pub fn hasPrefix(self: *const Self, text: []const u8) bool {
        return self.searchWithMode(text, .prefix) != null;
    }

    /// Check if text exactly matches any of the registered patterns.
    pub fn isExact(self: *const Self, text: []const u8) bool {
        return self.searchWithMode(text, .exact) != null;
    }

    /// Get the number of states (nodes) in the automaton.
    pub fn stateCount(self: *const Self) usize {
        return self.nodes.items.len;
    }

    /// Get the number of patterns added.
    pub fn patternCount(self: *const Self) usize {
        return self.pattern_count;
    }

    /// Lookup stored pattern length by pattern ID via iterative trie traversal.
    ///
    /// Uses an explicit DFS stack (iterative) instead of recursion to
    /// avoid stack overflow on deep tries with many nodes.
    fn getPatternLen(self: *const Self, pattern_id: usize) usize {
        if (self.nodes.items.len == 0) return 0;

        // Each stack entry: { node_index, depth }
        const Entry = struct { node_idx: usize, depth: usize };
        var stack = ArrayList(Entry).initCapacity(self.allocator, 16) catch return 0;
        defer stack.deinit(self.allocator);

        // Seed the stack with the root node at depth 0
        stack.appendAssumeCapacity(.{ .node_idx = 0, .depth = 0 });

        while (stack.items.len > 0) {
            const top = stack.pop();
            const node = &self.nodes.items[top.node_idx];

            // Check if this node stores the target pattern
            for (0..node.output_len) |i| {
                if (node.output[i] == pattern_id) {
                    return top.depth;
                }
            }

            // Push children onto the stack (iterate in insertion order)
            var child_it = node.children.iterator();
            while (child_it.next()) |entry| {
                stack.appendAssumeCapacity(.{
                    .node_idx = entry.value_ptr.*,
                    .depth = top.depth + 1,
                });
            }
        }

        return 0;
    }
};

// ============================================================
// Tests
// ============================================================

test "init and deinit" {
    var ac = AhoCorasick.init(std.testing.allocator);
    defer ac.deinit();

    try std.testing.expectEqual(@as(usize, 0), ac.stateCount());
    try std.testing.expectEqual(@as(usize, 0), ac.patternCount());
}

test "basic single pattern search" {
    var ac = AhoCorasick.init(std.testing.allocator);
    defer ac.deinit();

    try ac.addPattern("hello", 42);
    try ac.build();

    const result = ac.search("say hello world");
    try std.testing.expect(result != null);
    try std.testing.expectEqual(@as(usize, 42), result.?.pattern_id);
    try std.testing.expectEqual(@as(usize, 4), result.?.start);
    try std.testing.expectEqual(@as(usize, 9), result.?.end);

    try std.testing.expect(ac.search("no match here") == null);
    try std.testing.expect(ac.search("hell") == null);
}

test "multiple patterns - first match" {
    var ac = AhoCorasick.init(std.testing.allocator);
    defer ac.deinit();

    try ac.addPattern("he", 0);
    try ac.addPattern("she", 1);
    try ac.addPattern("his", 2);
    try ac.addPattern("hers", 3);
    try ac.build();

    // In "ahishers", "his" starts at index 1
    const result = ac.search("ahishers");
    try std.testing.expect(result != null);
    // "his" (id=2) at position 1 is found first
    try std.testing.expectEqual(@as(usize, 2), result.?.pattern_id);
    try std.testing.expectEqual(@as(usize, 1), result.?.start);
    try std.testing.expectEqual(@as(usize, 4), result.?.end);
}

test "multiple patterns - all matches" {
    var ac = AhoCorasick.init(std.testing.allocator);
    defer ac.deinit();

    try ac.addPattern("he", 0);
    try ac.addPattern("she", 1);
    try ac.addPattern("his", 2);
    try ac.addPattern("hers", 3);
    try ac.build();

    var results = ArrayList(MatchResult).initCapacity(std.testing.allocator, 16) catch unreachable;
    defer results.deinit(std.testing.allocator);

    try ac.findAll("ahishers", &results);

    // Should find: his(2), he(0), she(1), hers(3)
    try std.testing.expect(results.items.len >= 3);

    // Verify "his" at position 1
    var found_his = false;
    for (results.items) |m| {
        if (m.pattern_id == 2 and m.start == 1) {
            found_his = true;
        }
    }
    try std.testing.expect(found_his);
}

test "containsAny" {
    var ac = AhoCorasick.init(std.testing.allocator);
    defer ac.deinit();

    try ac.addPattern("strcpy", 0);
    try ac.addPattern("system", 1);
    try ac.addPattern("gets", 2);
    try ac.build();

    try std.testing.expect(ac.containsAny("call to strcpy is dangerous"));
    try std.testing.expect(ac.containsAny("system() call"));
    try std.testing.expect(!ac.containsAny("safe_function"));
}

test "empty pattern handling" {
    var ac = AhoCorasick.init(std.testing.allocator);
    defer ac.deinit();

    // Empty pattern is silently ignored
    try ac.addPattern("", 0);
    try std.testing.expectEqual(@as(usize, 0), ac.patternCount());
}

test "overlapping patterns" {
    var ac = AhoCorasick.init(std.testing.allocator);
    defer ac.deinit();

    try ac.addPattern("abc", 0);
    try ac.addPattern("bc", 1);
    try ac.addPattern("c", 2);
    try ac.build();

    var results = ArrayList(MatchResult).initCapacity(std.testing.allocator, 16) catch unreachable;
    defer results.deinit(std.testing.allocator);

    try ac.findAll("abc", &results);

    // "abc" contains all three: abc(0), bc(1), c(2)
    try std.testing.expectEqual(@as(usize, 3), results.items.len);
}

test "pattern at start and end" {
    var ac = AhoCorasick.init(std.testing.allocator);
    defer ac.deinit();

    try ac.addPattern("start", 0);
    try ac.addPattern("end", 1);
    try ac.build();

    try std.testing.expect(ac.containsAny("start of text"));
    try std.testing.expect(ac.containsAny("text at end"));
    try std.testing.expect(!ac.containsAny("middle"));
}

test "binary content matching" {
    var ac = AhoCorasick.init(std.testing.allocator);
    defer ac.deinit();

    try ac.addPattern(&[_]u8{ 0xDE, 0xAD }, 0);
    try ac.build();

    try std.testing.expect(ac.containsAny(&[_]u8{ 0x00, 0xDE, 0xAD, 0x00 }));
    try std.testing.expect(!ac.containsAny(&[_]u8{ 0xDE, 0xAE }));
}

test "duplicate patterns same ID" {
    var ac = AhoCorasick.init(std.testing.allocator);
    defer ac.deinit();

    try ac.addPattern("test", 99);
    try ac.addPattern("test", 99); // Same pattern, same ID
    try ac.build();

    var results = ArrayList(MatchResult).initCapacity(std.testing.allocator, 8) catch unreachable;
    defer results.deinit(std.testing.allocator);

    try ac.findAll("test", &results);
    // Should find at least one match
    try std.testing.expect(results.items.len >= 1);
    try std.testing.expectEqual(@as(usize, 99), results.items[0].pattern_id);
}

test "search before build" {
    var ac = AhoCorasick.init(std.testing.allocator);
    defer ac.deinit();

    try ac.addPattern("test", 0);
    // Don't build - search should return null gracefully
    try std.testing.expect(ac.search("test") == null);
}

test "state count tracking" {
    var ac = AhoCorasick.init(std.testing.allocator);
    defer ac.deinit();

    try ac.addPattern("ab", 0);
    try ac.addPattern("ac", 1);

    // Root + a + b + c = 4 states
    try std.testing.expectEqual(@as(usize, 4), ac.stateCount());
    try std.testing.expectEqual(@as(usize, 2), ac.patternCount());
}

test "prefix match mode" {
    var ac = AhoCorasick.init(std.testing.allocator);
    defer ac.deinit();

    try ac.addPattern("hello", 0);
    try ac.addPattern("world", 1);
    try ac.build();

    // "hello" appears at start
    try std.testing.expect(ac.hasPrefix("hello world"));
    // "world" appears at end, not at start
    try std.testing.expect(!ac.hasPrefix("say world"));
    // "world" appears at start
    try std.testing.expect(ac.hasPrefix("world hello"));
}

test "exact match mode" {
    var ac = AhoCorasick.init(std.testing.allocator);
    defer ac.deinit();

    try ac.addPattern("hello", 0);
    try ac.addPattern("world", 1);
    try ac.build();

    try std.testing.expect(ac.isExact("hello"));
    try std.testing.expect(ac.isExact("world"));
    try std.testing.expect(!ac.isExact("hello world"));
    try std.testing.expect(!ac.isExact("hell"));
}

test "real world patterns - C function names" {
    var ac = AhoCorasick.init(std.testing.allocator);
    defer ac.deinit();

    try ac.addPattern("strcpy", 0);
    try ac.addPattern("strcat", 1);
    try ac.addPattern("sprintf", 2);
    try ac.addPattern("gets", 3);
    try ac.addPattern("system", 4);
    try ac.addPattern("popen", 5);
    try ac.addPattern("malloc", 6);
    try ac.addPattern("free", 7);
    try ac.addPattern("memcpy", 8);
    try ac.build();

    try std.testing.expect(ac.containsAny("call to strcpy_s"));
    try std.testing.expect(ac.containsAny("using sprintf for output"));
    try std.testing.expect(ac.containsAny("system(\"ls\")"));
    try std.testing.expect(!ac.containsAny("my_custom_function"));
}

test "performance smoke test - many patterns" {
    var ac = AhoCorasick.init(std.testing.allocator);
    defer ac.deinit();

    const patterns = [_][]const u8{
        "std::",            "core::",     "alloc::",
        "__rust_",          "llvm.",      "__builtin_",
        "__cxa_",           "runtime.",   "unsafe",
        "extern",           "dlopen",     "dlsym",
        "mmap",             "munmap",     "pthread_",
        "signal(",          "fork(",      "exec",
        "reinterpret_cast", "const_cast", "static_cast",
        "malloc(",          "free(",      "new ",
        "delete ",
    };

    for (patterns, 0..) |p, i| {
        try ac.addPattern(p, i);
    }
    try ac.build();

    try std.testing.expect(ac.containsAny("std::vector<int>"));
    try std.testing.expect(ac.containsAny("core::fmt::write"));
    try std.testing.expect(ac.containsAny("__rust_alloc"));
    try std.testing.expect(ac.containsAny("llvm.lifetime.start"));
    try std.testing.expect(!ac.containsAny("my_function"));
    try std.testing.expect(!ac.containsAny("safe_code"));
}

test "match result positions" {
    var ac = AhoCorasick.init(std.testing.allocator);
    defer ac.deinit();

    try ac.addPattern("abc", 0);
    try ac.addPattern("def", 1);
    try ac.build();

    var results = ArrayList(MatchResult).initCapacity(std.testing.allocator, 8) catch unreachable;
    defer results.deinit(std.testing.allocator);

    try ac.findAll("abcdef", &results);

    // Should find "abc" at 0..3 and "def" at 3..6
    try std.testing.expectEqual(@as(usize, 2), results.items.len);

    // Sort by start position for deterministic check
    std.mem.sort(MatchResult, results.items, {}, struct {
        fn lessThan(_: void, a: MatchResult, b: MatchResult) bool {
            return a.start < b.start;
        }
    }.lessThan);

    try std.testing.expectEqual(@as(usize, 0), results.items[0].pattern_id);
    try std.testing.expectEqual(@as(usize, 0), results.items[0].start);
    try std.testing.expectEqual(@as(usize, 3), results.items[0].end);

    try std.testing.expectEqual(@as(usize, 1), results.items[1].pattern_id);
    try std.testing.expectEqual(@as(usize, 3), results.items[1].start);
    try std.testing.expectEqual(@as(usize, 6), results.items[1].end);
}

test "single character patterns" {
    var ac = AhoCorasick.init(std.testing.allocator);
    defer ac.deinit();

    try ac.addPattern("a", 0);
    try ac.addPattern("b", 1);
    try ac.addPattern("c", 2);
    try ac.build();

    var results = ArrayList(MatchResult).initCapacity(std.testing.allocator, 16) catch unreachable;
    defer results.deinit(std.testing.allocator);

    try ac.findAll("abcabc", &results);

    // Should find 6 matches: a(0), b(1), c(2), a(0), b(1), c(2)
    try std.testing.expectEqual(@as(usize, 6), results.items.len);
}

test "pattern not found in text" {
    var ac = AhoCorasick.init(std.testing.allocator);
    defer ac.deinit();

    try ac.addPattern("xyz", 0);
    try ac.addPattern("qwerty", 1);
    try ac.build();

    try std.testing.expect(ac.search("abcdefghijklmnop") == null);
    try std.testing.expect(!ac.containsAny("hello world"));
}

test "pattern is entire text" {
    var ac = AhoCorasick.init(std.testing.allocator);
    defer ac.deinit();

    try ac.addPattern("exact", 0);
    try ac.build();

    const result = ac.search("exact");
    try std.testing.expect(result != null);
    try std.testing.expectEqual(@as(usize, 0), result.?.start);
    try std.testing.expectEqual(@as(usize, 5), result.?.end);
}

test "consecutive patterns" {
    var ac = AhoCorasick.init(std.testing.allocator);
    defer ac.deinit();

    try ac.addPattern("ab", 0);
    try ac.addPattern("cd", 1);
    try ac.addPattern("ef", 2);
    try ac.build();

    var results = ArrayList(MatchResult).initCapacity(std.testing.allocator, 8) catch unreachable;
    defer results.deinit(std.testing.allocator);

    try ac.findAll("abcdef", &results);

    try std.testing.expectEqual(@as(usize, 3), results.items.len);
}

test "pattern with repeated characters" {
    var ac = AhoCorasick.init(std.testing.allocator);
    defer ac.deinit();

    try ac.addPattern("aaa", 0);
    try ac.addPattern("aa", 1);
    try ac.build();

    var results = ArrayList(MatchResult).initCapacity(std.testing.allocator, 16) catch unreachable;
    defer results.deinit(std.testing.allocator);

    try ac.findAll("aaaa", &results);

    // "aaaa" contains: aaa at 0, aa at 0, aaa at 1, aa at 1, aa at 2
    try std.testing.expect(results.items.len >= 3);
}
