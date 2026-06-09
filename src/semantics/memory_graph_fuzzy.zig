//! Fuzzy Matcher for Alloc/Free Function Pair Detection.
//!
//! Provides heuristic-based classification and pairing of allocation/deallocation
//! function names using suffix matching and prefix extraction.
//!
//! Extracted from memory_graph.zig to comply with the 1000-line limit.

const std = @import("std");

/// Classification of a function's role in memory management.
pub const FnClass = enum(u8) {
    /// Memory allocation function (malloc, calloc, new, etc.)
    alloc,
    /// Initialization function (init, _init)
    init,
    /// Factory/constructor function (create, _create)
    create,
    /// Resource opening function (open, dlopen)
    open,
    /// Memory deallocation function (free, dealloc, delete, etc.)
    free,
    /// Cleanup function (cleanup, finalize)
    cleanup,
    /// Destructor function (destroy, _destroy)
    destroy,
    /// Resource closing function (close, dlclose)
    close,
    /// Unknown/unclassified function
    other,
};

/// Fuzzy matcher for classifying and pairing alloc/free functions.
///
/// Uses case-insensitive suffix matching to classify function names
/// into categories, then pairs alloc-like with free-like functions
/// based on shared library prefixes.
pub const FuzzyMatcher = struct {
    /// Classify a function name into its memory management role.
    pub fn classify(fn_name: []const u8) FnClass {
        if (endsWithLower(fn_name, "free") or
            endsWithLower(fn_name, "_free") or
            endsWithLower(fn_name, "dealloc") or
            indexOfLower(fn_name, "dealloc") != null or
            endsWithLower(fn_name, "_drop") or
            endsWithLower(fn_name, "_release") or
            endsWithLower(fn_name, "drop") or
            endsWithLower(fn_name, "release"))
        {
            return .free;
        }

        if (endsWithLower(fn_name, "malloc") or
            endsWithLower(fn_name, "calloc") or
            endsWithLower(fn_name, "realloc") or
            endsWithLower(fn_name, "_alloc") or
            endsWithLower(fn_name, "alloc") or
            indexOfLower(fn_name, "alloc") != null)
        {
            return .alloc;
        }

        if (endsWithLower(fn_name, "_new") or
            indexOfLower(fn_name, "_new_") != null)
        {
            return .alloc;
        }

        if (endsWithLower(fn_name, "_delete") or
            indexOfLower(fn_name, "_delete_") != null)
        {
            return .free;
        }

        if (endsWithLower(fn_name, "_init")) {
            return .init;
        }

        if (endsWithLower(fn_name, "_cleanup") or
            endsWithLower(fn_name, "cleanup") or
            endsWithLower(fn_name, "finalize"))
        {
            return .cleanup;
        }

        if (endsWithLower(fn_name, "_create") or
            endsWithLower(fn_name, "create"))
        {
            return .create;
        }

        if (endsWithLower(fn_name, "_destroy") or
            endsWithLower(fn_name, "destroy"))
        {
            return .destroy;
        }

        if (endsWithLower(fn_name, "_open") or
            endsWithLower(fn_name, "dlopen"))
        {
            return .open;
        }

        if (endsWithLower(fn_name, "_close") or
            endsWithLower(fn_name, "dlclose"))
        {
            return .close;
        }

        return .other;
    }

    /// Check if two functions form a valid alloc/free pair.
    ///
    /// Matching criteria:
    ///   1. One must be alloc-like, the other free-like
    ///   2. Must share the same library prefix (e.g., "sqlite3")
    ///   3. Known suffix pairs must match (new/delete, malloc/free, etc.)
    pub fn isMatchingAllocFreePair(alloc_fn: []const u8, free_fn: []const u8) bool {
        if (!isAllocLike(alloc_fn) or !isFreeLike(free_fn)) {
            return false;
        }

        if (std.mem.eql(u8, alloc_fn, free_fn)) {
            return false;
        }

        const alloc_prefix = extractLibPrefix(alloc_fn);
        const free_prefix = extractLibPrefix(free_fn);

        if (alloc_prefix.len == 0 or free_prefix.len == 0) {
            return false;
        }

        if (!std.mem.eql(u8, alloc_prefix, free_prefix)) {
            return false;
        }

        if (endsWithLower(alloc_fn, "new") and
            endsWithLower(free_fn, "delete"))
        {
            return true;
        }

        if (endsWithLower(alloc_fn, "malloc") and
            endsWithLower(free_fn, "free"))
        {
            return true;
        }

        if (endsWithLower(alloc_fn, "alloc") and
            endsWithLower(free_fn, "free"))
        {
            return true;
        }

        if (endsWithLower(alloc_fn, "calloc") and
            endsWithLower(free_fn, "free"))
        {
            return true;
        }

        if (endsWithLower(alloc_fn, "realloc") and
            endsWithLower(free_fn, "free"))
        {
            return true;
        }

        if (endsWithLower(alloc_fn, "init") and
            endsWithLower(free_fn, "cleanup"))
        {
            return true;
        }

        if (endsWithLower(alloc_fn, "create") and
            endsWithLower(free_fn, "destroy"))
        {
            return true;
        }

        if (endsWithLower(alloc_fn, "open") and
            endsWithLower(free_fn, "close"))
        {
            return true;
        }

        if (endsWithLower(alloc_fn, "dlopen") and
            endsWithLower(free_fn, "dlclose"))
        {
            return true;
        }

        if (endsWithLower(alloc_fn, "new")) {
            return endsWithLower(free_fn, "free");
        }

        return false;
    }

    fn isAllocLike(fn_name: []const u8) bool {
        const class = classify(fn_name);
        return class == .alloc or class == .init or class == .create or class == .open;
    }

    fn isFreeLike(fn_name: []const u8) bool {
        const class = classify(fn_name);
        return class == .free or class == .cleanup or class == .destroy or class == .close;
    }

    /// Extract the library/module prefix from a function name.
    ///
    /// Examples:
    ///   "sqlite3_malloc" → "sqlite3"
    ///   "myObj_Create" → "myObj"
    ///   "free" → "" (no prefix)
    fn extractLibPrefix(fn_name: []const u8) []const u8 {
        if (fn_name.len == 0) return "";

        var end: usize = 0;
        while (end < fn_name.len and fn_name[end] != '_' and fn_name[end] != 0) {
            if (fn_name[end] >= 'A' and fn_name[end] <= 'Z') {
                end += 1;
            } else if (fn_name[end] >= 'a' and fn_name[end] <= 'z') {
                end += 1;
            } else if (fn_name[end] >= '0' and fn_name[end] <= '9') {
                end += 1;
            } else {
                break;
            }
        }

        if (end == 0) return "";

        const prefix = fn_name[0..end];

        if (prefix.len >= 3 and std.mem.startsWith(u8, fn_name[end..], "_")) {
            return prefix;
        }

        for (0..end) |i| {
            if (fn_name[i] == '_') {
                return fn_name[0..i];
            }
        }

        return prefix;
    }

    /// Case-insensitive endsWith. Zero allocation.
    fn endsWithLower(haystack: []const u8, needle: []const u8) bool {
        if (needle.len > haystack.len) return false;
        const offset = haystack.len - needle.len;
        for (needle, 0..) |ch, i| {
            if (std.ascii.toLower(haystack[offset + i]) != ch) return false;
        }
        return true;
    }

    /// Case-insensitive indexOf. Zero allocation.
    fn indexOfLower(haystack: []const u8, needle: []const u8) ?usize {
        if (needle.len > haystack.len) return null;
        const limit = haystack.len - needle.len;
        var i: usize = 0;
        while (i <= limit) : (i += 1) {
            var matched = true;
            for (needle, 0..) |ch, j| {
                if (std.ascii.toLower(haystack[i + j]) != ch) {
                    matched = false;
                    break;
                }
            }
            if (matched) return i;
        }
        return null;
    }
};
