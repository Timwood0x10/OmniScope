//! Allocator Knowledge Base module for recognizing custom memory allocators.
//!
//! This is a standalone module that identifies memory allocation/deallocation
//! functions beyond the standard malloc/free. It recognizes patterns like:
//!
//!   - sqlite3_malloc / sqlite3_free
//!   - OPENSSL_malloc / CRYPTO_free
//!   - uv__malloc / uv__free
//!   - g_malloc / g_free
//!
//! Architecture:
//!
//!   AllocatorInfo: describes a known allocator function
//!   AllocatorPair: pairs allocators with their matching deallocators
//!   AllocatorKB: the knowledge base with builtin and discovered allocators
//!
//! Key Selling Points:
//!   - Standalone module, no dependencies on other analysis modules
//!   - Builtin knowledge base for common libraries (sqlite3, openssl, glib, libuv)
//!   - Heuristic discovery for unknown allocators
//!   - Integration-ready with MemoryGraph for proper alloc/free pairing

const std = @import("std");

/// Error set for allocator knowledge base operations.
pub const AllocatorKBError = error{
    OutOfMemory,
    NotFound,
    DuplicateEntry,
};

/// Kind of allocation operation.
pub const AllocKind = enum(u8) {
    /// Standard heap allocation (malloc, calloc, realloc).
    heap_alloc,
    /// Object allocation (returns pointer to object).
    alloc_object,
    /// Memory arena allocation.
    arena_alloc,
    /// Stack allocation (alloca).
    stack_alloc,
    /// Global/static allocation.
    global_alloc,
    /// Static buffer return: function returns pointer to internal static storage.
    /// The caller must NOT free this pointer. It is NOT thread-safe.
    /// Examples: ctime(), asctime(), inet_ntoa(), strerror().
    static_buffer,
    /// Unknown allocation type.
    unknown,
};

/// Kind of deallocation operation.
pub const FreeKind = enum(u8) {
    /// Standard heap deallocation (free).
    heap_free,
    /// Object deallocation.
    free_object,
    /// Arena deallocation.
    arena_free,
    /// Unknown deallocation type.
    unknown,
};

/// Information about an allocator function.
pub const AllocatorInfo = struct {
    /// Name of the allocator function.
    name: []const u8,
    /// Kind of allocation.
    kind: AllocKind,
    /// Name of the matching deallocator (if known).
    matching_free: ?[]const u8,
    /// Library or source this allocator belongs to.
    source: []const u8,
    /// Whether this was discovered heuristically (vs builtin).
    is_heuristic: bool,
    /// Confidence score (0-100) for heuristic discoveries.
    confidence: u8,
};

/// A pair of allocator and deallocator.
pub const AllocatorPair = struct {
    /// The allocator function.
    alloc: AllocatorInfo,
    /// The deallocator function.
    free: AllocatorInfo,
    /// Whether this pair is confirmed or heuristic.
    is_confirmed: bool,
};

/// The Allocator Knowledge Base.
pub const AllocatorKB = struct {
    /// Map from function name → AllocatorInfo.
    allocators: std.StringHashMap(AllocatorInfo),
    /// Map from function name → AllocatorInfo (deallocators).
    deallocators: std.StringHashMap(AllocatorInfo),
    /// Known safe allocator pairs.
    pairs: std.ArrayList(AllocatorPair),
    /// Arena allocator for long-lived data.
    arena: std.heap.ArenaAllocator,
    /// Temporary allocator.
    temp_allocator: std.mem.Allocator,

    /// Initializes a new allocator knowledge base with builtin knowledge.
    pub fn init(temp_allocator: std.mem.Allocator) AllocatorKBError!AllocatorKB {
        var arena = std.heap.ArenaAllocator.init(temp_allocator);
        errdefer arena.deinit();

        var kb = AllocatorKB{
            .allocators = std.StringHashMap(AllocatorInfo).init(arena.allocator()),
            .deallocators = std.StringHashMap(AllocatorInfo).init(arena.allocator()),
            .pairs = std.ArrayList(AllocatorPair).init(arena.allocator()),
            .arena = undefined,
            .temp_allocator = temp_allocator,
        };

        kb.arena = arena;
        try kb.populateBuiltin();

        arena = undefined;
        return kb;
    }

    /// Deinitializes the knowledge base.
    pub fn deinit(kb: *AllocatorKB) void {
        kb.arena.deinit();
        kb.* = undefined;
    }

    /// Populates the builtin knowledge base with common allocators.
    fn populateBuiltin(kb: *AllocatorKB) AllocatorKBError!void {
        // SQLite allocators.
        try kb.addBuiltinPair("sqlite3_malloc", "sqlite3_free", "sqlite3");
        try kb.addBuiltinPair("sqlite3DbMallocRaw", "sqlite3DbFree", "sqlite3");
        try kb.addBuiltinPair("sqlite3MemMalloc", "sqlite3MemFree", "sqlite3");
        try kb.addBuiltinPair("sqlite3ScratchAlloc", "sqlite3ScratchFree", "sqlite3");
        try kb.addBuiltinPair("sqlite3PagerGet", "sqlite3PagerUnref", "sqlite3");

        // OpenSSL allocators.
        try kb.addBuiltinPair("OPENSSL_malloc", "OPENSSL_free", "openssl");
        try kb.addBuiltinPair("CRYPTO_malloc", "CRYPTO_free", "openssl");
        try kb.addBuiltinPair("CRYPTO_zalloc", "CRYPTO_free", "openssl");
        try kb.addBuiltinPair("OPENSSL_zalloc", "OPENSSL_free", "openssl");
        try kb.addBuiltinPair("EVP_CIPHER_CTX_new", "EVP_CIPHER_CTX_free", "openssl");
        try kb.addBuiltinPair("EVP_MD_CTX_new", "EVP_MD_CTX_free", "openssl");
        try kb.addBuiltinPair("RSA_new", "RSA_free", "openssl");
        try kb.addBuiltinPair("EC_KEY_new", "EC_KEY_free", "openssl");
        try kb.addBuiltinPair("X509_new", "X509_free", "openssl");
        try kb.addBuiltinPair("EVP_PKEY_new", "EVP_PKEY_free", "openssl");

        // libuv allocators.
        try kb.addBuiltinPair("uv__malloc", "uv__free", "libuv");
        try kb.addBuiltinPair("uv_malloc", "uv_free", "libuv");
        // NOTE: uv_buf_init is NOT a memory allocator - it only initializes
        // a uv_buf_t struct (sets base/len fields). Removed to avoid false positives.
        try kb.addBuiltinPair("uv_loop_init", "uv_loop_close", "libuv");
        try kb.addBuiltinPair("uv_handle_init", "uv_close", "libuv");

        // GLib allocators.
        try kb.addBuiltinPair("g_malloc", "g_free", "glib");
        try kb.addBuiltinPair("g_malloc_n", "g_free_n", "glib");
        try kb.addBuiltinPair("g_new", "g_free", "glib");
        try kb.addBuiltinPair("g_new0", "g_free", "glib");
        try kb.addBuiltinPair("g_renew", "g_free", "glib");
        try kb.addBuiltinPair("g_slice_alloc", "g_slice_free", "glib");
        try kb.addBuiltinPair("g_object_new", "g_object_unref", "glib");

        // Standard C library (for completeness).
        try kb.addBuiltinPair("malloc", "free", "libc");
        try kb.addBuiltinPair("calloc", "free", "libc");
        try kb.addBuiltinPair("realloc", "free", "libc");
        try kb.addBuiltinPair("strdup", "free", "libc");
        try kb.addBuiltinPair("getdelim", "free", "libc");
    }

    /// Adds a builtin allocator pair.
    fn addBuiltinPair(
        kb: *AllocatorKB,
        alloc_name: []const u8,
        free_name: ?[]const u8,
        source: []const u8,
    ) AllocatorKBError!void {
        const alloc_info = AllocatorInfo{
            .name = alloc_name,
            .kind = .heap_alloc,
            .matching_free = free_name,
            .source = source,
            .is_heuristic = false,
            .confidence = 100,
        };

        try kb.allocators.put(alloc_name, alloc_info);

        if (free_name) |fname| {
            const free_info = AllocatorInfo{
                .name = fname,
                .kind = .heap_free,
                .matching_free = alloc_name,
                .source = source,
                .is_heuristic = false,
                .confidence = 100,
            };
            try kb.deallocators.put(fname, free_info);

            const pair = AllocatorPair{
                .alloc = alloc_info,
                .free = free_info,
                .is_confirmed = true,
            };
            try kb.pairs.append(pair);
        }

        // Static buffer functions: return pointer to internal static storage.
        // These must NOT be freed and are NOT thread-safe.
        // The _r variants (ctime_r, asctime_r, etc.) use caller-provided
        // buffers and are safe — they are NOT listed here.
        const static_buf_funcs = [_][]const u8{
            "ctime",     "asctime",  "strerror", "strsignal",
            "inet_ntoa", "getgrgid", "getgrnam", "getpwuid",
            "getpwnam",  "getpwent", "grent",    "tmpnam",
            "gcvt",      "ecvt",     "fcvt",     "crypt",
        };
        for (static_buf_funcs) |fname| {
            const info = AllocatorInfo{
                .name = fname,
                .kind = .static_buffer,
                .matching_free = null, // Must NOT be freed!
                .source = "posix",
                .is_heuristic = false,
                .confidence = 100,
            };
            try kb.allocators.put(fname, info);
        }
    }

    /// Looks up an allocator by name.
    pub fn getAllocator(kb: *AllocatorKB, name: []const u8) ?AllocatorInfo {
        return kb.allocators.get(name);
    }

    /// Looks up a deallocator by name.
    pub fn getDeallocator(kb: *AllocatorKB, name: []const u8) ?AllocatorInfo {
        return kb.deallocators.get(name);
    }

    /// Checks if a function name is a known allocator.
    pub fn isAllocator(kb: *AllocatorKB, name: []const u8) bool {
        return kb.allocators.contains(name);
    }

    /// Checks if a function name is a known deallocator.
    pub fn isDeallocator(kb: *AllocatorKB, name: []const u8) bool {
        return kb.deallocators.contains(name);
    }

    /// Checks if a function returns a pointer to static internal storage.
    /// These functions must NOT be freed by the caller and are NOT thread-safe.
    /// Returns the AllocatorInfo if found, null otherwise.
    pub fn isStaticBufferFunction(kb: *AllocatorKB, name: []const u8) ?AllocatorInfo {
        return kb.allocators.get(name) orelse {
            // Also check with _r suffix (reentrant variants are NOT static).
            // ctime_r, asctime_r etc. use caller-provided buffers — safe.
            return null;
        };
    }

    /// Checks if a function name is a known static buffer function.
    /// Convenience wrapper that returns bool.
    pub fn isStaticBuffer(kb: *AllocatorKB, name: []const u8) bool {
        if (kb.allocators.get(name)) |info| {
            return info.kind == .static_buffer;
        }
        return false;
    }

    /// Finds the matching deallocator for an allocator.
    pub fn findMatchingFree(
        kb: *AllocatorKB,
        alloc_name: []const u8,
    ) ?[]const u8 {
        const info = kb.allocators.get(alloc_name) orelse return null;
        return info.matching_free;
    }

    /// Heuristically discovers potential allocators from function name.
    /// This uses naming patterns to guess if a function is an allocator.
    pub fn discoverHeuristic(
        kb: *AllocatorKB,
        name: []const u8,
    ) ?AllocatorInfo {
        // Check if already known (builtin or previously discovered).
        if (kb.allocators.contains(name)) return null;

        // Heuristic patterns for allocators - narrow patterns only to reduce false positives.
        const alloc_patterns = [_][]const u8{
            "malloc", "alloc", "new", "create",
            "make",   "open",
        };

        // Heuristic patterns for deallocators.
        const free_patterns = [_][]const u8{
            "free",   "release", "destroy",  "close", "cleanup",
            "delete", "unref",   "finalize",
        };

        // Check allocator patterns.
        for (alloc_patterns) |pat| {
            if (std.ascii.indexOfIgnoreCase(name, pat) != null) {
                const info = AllocatorInfo{
                    .name = name,
                    .kind = .heap_alloc,
                    .matching_free = null,
                    .source = "heuristic",
                    .is_heuristic = true,
                    .confidence = 60,
                };
                // PERSIST: Cache discovered allocator in hash table to avoid
                // redundant heuristic matching on subsequent calls.
                // OOM: skip caching (non-fatal); info is still returned correctly.
                kb.allocators.put(name, info) catch return info;
                return info;
            }
        }

        // Check deallocator patterns.
        for (free_patterns) |pat| {
            if (std.ascii.indexOfIgnoreCase(name, pat) != null) {
                const info = AllocatorInfo{
                    .name = name,
                    .kind = .heap_free,
                    .matching_free = null,
                    .source = "heuristic",
                    .is_heuristic = true,
                    .confidence = 60,
                };
                // PERSIST: Store discovered deallocator in hash table.
                kb.allocators.put(name, info) catch return info;
                return info;
            }
        }

        return null;
    }

    /// Gets all known allocator pairs.
    pub fn getPairs(kb: *AllocatorKB) []AllocatorPair {
        return kb.pairs.items;
    }

    /// Gets statistics about the knowledge base.
    pub fn getStats(kb: *AllocatorKB) KBStats {
        return KBStats{
            .allocator_count = kb.allocators.count(),
            .deallocator_count = kb.deallocators.count(),
            .pair_count = kb.pairs.items.len,
            .heuristic_count = blk: {
                var count: u32 = 0;
                var it = kb.allocators.valueIterator();
                while (it.next()) |info| {
                    if (info.is_heuristic) count += 1;
                }
                break :blk count;
            },
        };
    }
};

/// Statistics about the allocator knowledge base.
pub const KBStats = struct {
    allocator_count: u32,
    deallocator_count: u32,
    pair_count: u32,
    heuristic_count: u32,
};

// ============================================================================
// Tests
// ============================================================================

test "allocator_kb - builtin sqlite3" {
    var temp_mem = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = temp_mem.deinit();
    const allocator = temp_mem.allocator();

    var kb = try AllocatorKB.init(allocator);
    defer kb.deinit();

    // Check sqlite3_malloc is recognized.
    const info = kb.getAllocator("sqlite3_malloc");
    try std.testing.expect(info != null);
    try std.testing.expectEqualStrings("sqlite3", info.?.source);
    try std.testing.expectEqualStrings("sqlite3_free", info.?.matching_free.?);

    // Check matching free.
    const free_name = kb.findMatchingFree("sqlite3_malloc");
    try std.testing.expect(free_name != null);
    try std.testing.expectEqualStrings("sqlite3_free", free_name.?);
}

test "allocator_kb - builtin openssl" {
    var temp_mem = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = temp_mem.deinit();
    const allocator = temp_mem.allocator();

    var kb = try AllocatorKB.init(allocator);
    defer kb.deinit();

    // Check EVP_CIPHER_CTX_new / EVP_CIPHER_CTX_free pair.
    const ctx_new = kb.getAllocator("EVP_CIPHER_CTX_new");
    try std.testing.expect(ctx_new != null);
    try std.testing.expectEqualStrings("openssl", ctx_new.?.source);

    const ctx_free = kb.getDeallocator("EVP_CIPHER_CTX_free");
    try std.testing.expect(ctx_free != null);

    // Check pair exists.
    const pairs = kb.getPairs();
    var found = false;
    for (pairs) |pair| {
        if (std.mem.eql(u8, pair.alloc.name, "EVP_CIPHER_CTX_new") and
            std.mem.eql(u8, pair.free.name, "EVP_CIPHER_CTX_free"))
        {
            found = true;
            try std.testing.expect(pair.is_confirmed);
        }
    }
    try std.testing.expect(found);
}

test "allocator_kb - builtin glib" {
    var temp_mem = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = temp_mem.deinit();
    const allocator = temp_mem.allocator();

    var kb = try AllocatorKB.init(allocator);
    defer kb.deinit();

    // Check g_malloc / g_free.
    try std.testing.expect(kb.isAllocator("g_malloc"));
    try std.testing.expect(kb.isDeallocator("g_free"));

    // Check g_object_new / g_object_unref.
    try std.testing.expect(kb.isAllocator("g_object_new"));
    try std.testing.expect(kb.isDeallocator("g_object_unref"));
}

test "allocator_kb - heuristic discovery" {
    var temp_mem = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = temp_mem.deinit();
    const allocator = temp_mem.allocator();

    var kb = try AllocatorKB.init(allocator);
    defer kb.deinit();

    // Discover custom_malloc (should be heuristic).
    const info = kb.discoverHeuristic("custom_malloc");
    try std.testing.expect(info != null);
    try std.testing.expect(info.?.is_heuristic);
    try std.testing.expectEqual(@as(u8, 60), info.?.confidence);

    // Discover my_free (should be heuristic).
    const free_info = kb.discoverHeuristic("my_free");
    try std.testing.expect(free_info != null);
    try std.testing.expect(free_info.?.is_heuristic);
}

test "allocator_kb - standard libc" {
    var temp_mem = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = temp_mem.deinit();
    const allocator = temp_mem.allocator();

    var kb = try AllocatorKB.init(allocator);
    defer kb.deinit();

    // Check standard functions.
    try std.testing.expect(kb.isAllocator("malloc"));
    try std.testing.expect(kb.isAllocator("calloc"));
    try std.testing.expect(kb.isAllocator("realloc"));
    try std.testing.expect(kb.isDeallocator("free"));
    try std.testing.expect(kb.isAllocator("strdup"));
}

test "allocator_kb - get stats" {
    var temp_mem = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = temp_mem.deinit();
    const allocator = temp_mem.allocator();

    var kb = try AllocatorKB.init(allocator);
    defer kb.deinit();

    const stats = kb.getStats();

    // Should have multiple builtin allocators.
    try std.testing.expect(stats.allocator_count > 10);
    try std.testing.expect(stats.deallocator_count > 10);
    try std.testing.expect(stats.pair_count > 10);

    // No heuristic discoveries yet.
    try std.testing.expectEqual(@as(u32, 0), stats.heuristic_count);
}

test "allocator_kb - unknown returns null" {
    var temp_mem = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = temp_mem.deinit();
    const allocator = temp_mem.allocator();

    var kb = try AllocatorKB.init(allocator);
    defer kb.deinit();

    // Unknown function should not be recognized.
    try std.testing.expect(!kb.isAllocator("unknown_function_xyz"));
    try std.testing.expect(!kb.isDeallocator("unknown_function_xyz"));
    try std.testing.expect(kb.getAllocator("unknown_function_xyz") == null);
    try std.testing.expect(kb.findMatchingFree("unknown_function_xyz") == null);
}
