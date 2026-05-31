//! FFI Contract Database Engine - Provides lifecycle rules for common C libraries.
//!
//! Answers questions like:
//!   - "Should this allocation be reported as potential leak?"
//!   - "Is this release function valid for the given allocation?"
//!   - "What is the correct way to free this object?"
//!
//! The database encodes domain knowledge about common C library APIs so that
//! OmniScope can distinguish real leaks from false positives and detect
//! incorrect allocate/release pairings (e.g., SSL_new + BIO_free).
//!
//! Data is loaded from built-in rules embedded at compile time. TOML file
//! loading is planned for future enhancement when stable TOML parsing is available.

const std = @import("std");
const log = @import("../common/log.zig");

// ============================================================================
// Public Types
// ============================================================================

/// Ownership model for FFI resources — who is responsible for releasing?
pub const OwnershipModel = enum {
    /// Caller must call release function (most common: malloc, SSL_CTX_new)
    caller,
    /// Callee manages internally (GC, pool, etc.) — don't report leak
    callee,
    /// Garbage collected — never report as leak
    gc,
    /// Custom allocator with special semantics — conservative: report
    custom,
    /// Borrowed reference — caller must NOT free
    borrowed,
};

/// Result of checking whether an alloc/release pair is correct
pub const PairMatchResult = enum {
    /// Correct pairing (e.g., SSL_new + SSL_free)
    valid_pair,
    /// Wrong release function (e.g., SSL_new + BIO_free) → POTENTIAL BUG!
    mismatch,
    /// Allocation function not found in database
    unknown_alloc,
    /// Release function not found in database
    unknown_release,
};

/// A single allocate/release rule within a library
pub const AllocPairRule = struct {
    /// Human-readable name for this resource type (e.g., "SSL_CTX", "BIO")
    name: []const u8,

    /// Function names that allocate this resource
    alloc_funcs: []const []const u8,

    /// Valid function names that release this resource
    release_funcs: []const []const u8,

    /// Who owns the resource?
    ownership: OwnershipModel,

    /// Confidence in this rule (0.0–1.0)
    confidence: f32 = 1.0,

    /// Optional notes about usage pitfalls
    note: ?[]const u8 = null,
};

/// Managed type info for GC-managed or special-lifecycle resources
pub const ManagedTypeInfo = struct {
    /// Type name patterns that match this managed category
    type_patterns: []const []const u8,

    /// Management model
    model: OwnershipModel,

    /// Retain/increment-ref functions (if applicable)
    retain_funcs: []const []const u8 = &.{},

    /// Release/decrement-ref functions
    release_funcs: []const []const u8 = &.{},
};

/// A library's complete contract definition
pub const LibraryContract = struct {
    /// Library identifier (e.g., "openssl", "sqlite")
    name: []const u8,

    /// Human-readable description
    description: ?[]const u8 = null,

    /// All allocate/release pair rules for this library
    pairs: []const AllocPairRule,

    /// Managed type info (GC types, custom allocators, etc.)
    managed_types: ?[]const ManagedTypeInfo = null,

    /// Is this library historically error-prone? Used for severity boosting.
    error_prone: bool = false,
};

// ============================================================================
// FFIContractDB — Main database type
// ============================================================================

/// FFI Contract Database: queries lifecycle rules for common C libraries.
///
/// Usage:
///   var db = try FFIContractDB.init(allocator);
///   defer db.deinit();
///
///   if (!db.shouldReportLeak("JSObjectMake")) {
///       // GC-managed, skip
///   }
///   if (db.isValidRelease("SSL_new", "BIO_free") == .mismatch) {
///       // Wrong pairing detected!
///   }
pub const FFIContractDB = struct {
    allocator: std.mem.Allocator,
    libraries: []const LibraryContract,

    /// Initialize the contract database with built-in rules.
    /// No file I/O needed — all data is embedded at compile time.
    pub fn init(_: std.mem.Allocator) !FFIContractDB {
        return .{
            .allocator = undefined,
            .libraries = builtinLibraries(),
        };
    }

    /// Clean up database resources.
    pub fn deinit(self: *FFIContractDB) void {
        self.* = undefined;
    }

    // ── Query API ──

    /// Should this allocation be reported as a potential leak?
    ///
    /// Returns false for:
    ///   - GC-managed objects (JSC, JNI LocalRef)
    ///   - Callee-owned resources
    ///   - Borrowed references
    ///
    /// Returns true for:
    ///   - Caller-owned allocations (malloc, SSL_CTX_new, sqlite3_open)
    ///   - Unknown functions (conservative default)
    ///
    /// This is the primary FP-suppression hook for CrossLangDataFlow.
    pub fn shouldReportLeak(self: *const FFIContractDB, alloc_func: []const u8) bool {
        // Check all library contracts
        for (self.libraries) |lib| {
            // Check allocate/release pairs
            for (lib.pairs) |rule| {
                for (rule.alloc_funcs) |pattern| {
                    if (matchFuncName(alloc_func, pattern)) {
                        return switch (rule.ownership) {
                            .gc, .callee, .borrowed => false,
                            .caller, .custom => true,
                        };
                    }
                }
            }

            // Check managed types (GC-managed, etc.)
            if (lib.managed_types) |managed| {
                for (managed) |mt| {
                    for (mt.type_patterns) |pattern| {
                        if (matchFuncName(alloc_func, pattern)) {
                            return mt.model != .gc;
                        }
                    }
                }
            }
        }

        // Unknown function → conservative: report potential leak
        return true;
    }

    /// Is this release function valid for the given allocation?
    ///
    /// Checks whether `release_func` is in the valid release set for
    /// the resource allocated by `alloc_func`.
    ///
    /// Returns:
    ///   .valid_pair     — correct pairing (SSL_new + SSL_free)
    ///   .mismatch      — wrong release function (SSL_new + BIO_free) → BUG!
    ///   .unknown_alloc — alloc_func not in database
    ///   .unknown_release — no rule found (can't validate)
    pub fn isValidRelease(
        self: *const FFIContractDB,
        alloc_func: []const u8,
        release_func: []const u8,
    ) PairMatchResult {
        const rule = self.findRuleForAlloc(alloc_func) orelse return .unknown_alloc;

        // Check if release_func is in the valid releases list
        for (rule.release_funcs) |valid_release| {
            if (matchFuncName(release_func, valid_release)) {
                return .valid_pair;
            }
        }

        // Release function doesn't match any valid release → mismatch bug
        if (libIsErrorProne(self, alloc_func)) {
            log.warn("CONTRACT-MISMATCH: {s} released by {s} (expected one of: {s})", .{
                alloc_func,
                release_func,
                rule.name,
            });
        }
        return .mismatch;
    }

    /// Get the correct release function(s) for an allocation function.
    ///
    /// Returns null if the allocation function is unknown.
    pub fn getExpectedReleases(
        self: *const FFIContractDB,
        alloc_func: []const u8,
    ) ?[]const []const u8 {
        const rule = self.findRuleForAlloc(alloc_func) orelse return null;
        return rule.release_funcs;
    }

    /// Get the ownership model for an allocation function.
    ///
    /// Returns null if the function is unknown.
    pub fn getOwnership(
        self: *const FFIContractDB,
        func_name: []const u8,
    ) ?OwnershipModel {
        const rule = self.findRuleForAlloc(func_name) orelse return null;
        return rule.ownership;
    }

    /// Is this function from a historically error-prone library?
    ///
    /// Used to boost confidence/score for issues involving these libraries.
    pub fn isErrorProneLib(self: *const FFIContractDB, func_name: []const u8) bool {
        return libIsErrorProne(self, func_name);
    }

    /// Get all known allocation function names across all libraries.
    /// Returns empty slice — callers should iterate libraries directly.
    pub fn getAllAllocFuncs(self: *const FFIContractDB) []const []const u8 {
        _ = self;
        return &.{};
    }

    /// Look up a specific rule by allocation function name.
    /// Internal use; prefer public query APIs.
    pub fn findRuleForAlloc(
        self: *const FFIContractDB,
        alloc_func: []const u8,
    ) ?*const AllocPairRule {
        for (self.libraries) |lib| {
            for (lib.pairs) |*rule| {
                for (rule.alloc_funcs) |pattern| {
                    if (matchFuncName(alloc_func, pattern)) {
                        return rule;
                    }
                }
            }
        }
        return null;
    }

    // ── Helpers ──

    /// Match a function name against a pattern.
    /// Supports exact match and substring containment.
    fn matchFuncName(haystack: []const u8, needle: []const u8) bool {
        return std.mem.eql(u8, haystack, needle) or
            std.mem.indexOf(u8, haystack, needle) != null;
    }
};

// ============================================================================
// Built-in Contract Data (embedded at compile time)
// ============================================================================

/// Returns the full set of built-in library contracts.
/// This data is embedded at comptime — no file I/O required.
fn builtinLibraries() []const LibraryContract {
    return &[_]LibraryContract{
        // ── OpenSSL / BoringSSL ──────────────────────────────────────
        .{
            .name = "openssl",
            .description = "BoringSSL/OpenSSL object lifecycle",
            .error_prone = true,
            .pairs = &[_]AllocPairRule{
                .{
                    .name = "SSL_CTX",
                    .alloc_funcs = &[_][]const u8{ "SSL_CTX_new", "TLS_method", "TLS_server_method", "TLS_client_method" },
                    .release_funcs = &[_][]const u8{"SSL_CTX_free"},
                    .ownership = .caller,
                    .confidence = 0.95,
                },
                .{
                    .name = "SSL",
                    .alloc_funcs = &[_][]const u8{ "SSL_new", "SSL_dup" },
                    .release_funcs = &[_][]const u8{"SSL_free"},
                    .ownership = .caller,
                    .confidence = 0.95,
                },
                .{
                    .name = "BIO",
                    .alloc_funcs = &[_][]const u8{ "BIO_new", "BIO_new_file", "BIO_new_mem_buf", "BIO_s_mem" },
                    .release_funcs = &[_][]const u8{ "BIO_free", "BIO_free_all" },
                    .ownership = .caller,
                },
                .{
                    .name = "X509",
                    .alloc_funcs = &[_][]const u8{ "PEM_read_bio_X509", "PEM_read_X509", "d2i_X509", "X509_new" },
                    .release_funcs = &[_][]const u8{"X509_free"},
                    .ownership = .caller,
                },
                .{
                    .name = "EVP_PKEY",
                    .alloc_funcs = &[_][]const u8{ "PEM_read_bio_PrivateKey", "PEM_read_bio_PUBKEY", "d2i_AutoPrivateKey" },
                    .release_funcs = &[_][]const u8{"EVP_PKEY_free"},
                    .ownership = .caller,
                },
                .{
                    .name = "EVP_CIPHER_CTX",
                    .alloc_funcs = &[_][]const u8{"EVP_CIPHER_CTX_new"},
                    .release_funcs = &[_][]const u8{"EVP_CIPHER_CTX_free"},
                    .ownership = .caller,
                },
                .{
                    .name = "EVP_MD_CTX",
                    .alloc_funcs = &[_][]const u8{"EVP_MD_CTX_new"},
                    .release_funcs = &[_][]const u8{"EVP_MD_CTX_free"},
                    .ownership = .caller,
                },
                .{
                    .name = "RSA",
                    .alloc_funcs = &[_][]const u8{"RSA_new"},
                    .release_funcs = &[_][]const u8{"RSA_free"},
                    .ownership = .caller,
                },
                .{
                    .name = "BIGNUM",
                    .alloc_funcs = &[_][]const u8{"BN_new"},
                    .release_funcs = &[_][]const u8{"BN_free"},
                    .ownership = .caller,
                },
            },
            .managed_types = &[_]ManagedTypeInfo{
                .{
                    .type_patterns = &[_][]const u8{"OPENSSL_mem_fn"},
                    .model = .custom,
                },
            },
        },

        // ── SQLite ───────────────────────────────────────────────────
        .{
            .name = "sqlite",
            .description = "SQLite database handle and statement management",
            .error_prone = true,
            .pairs = &[_]AllocPairRule{
                .{
                    .name = "database_connection",
                    .alloc_funcs = &[_][]const u8{ "sqlite3_open", "sqlite3_open_v2", "sqlite3_open16" },
                    .release_funcs = &[_][]const u8{ "sqlite3_close", "sqlite3_close_v2" },
                    .ownership = .caller,
                },
                .{
                    .name = "prepared_statement",
                    .alloc_funcs = &[_][]const u8{ "sqlite3_prepare_v2", "sqlite3_prepare16", "sqlite3_prepare_v3" },
                    .release_funcs = &[_][]const u8{"sqlite3_finalize"},
                    .ownership = .caller,
                    .confidence = 0.98,
                },
                .{
                    .name = "blob",
                    .alloc_funcs = &[_][]const u8{ "sqlite3_blob_open", "sqlite3_blob_reopen" },
                    .release_funcs = &[_][]const u8{"sqlite3_blob_close"},
                    .ownership = .caller,
                },
                .{
                    .name = "sqlite_malloc",
                    .alloc_funcs = &[_][]const u8{ "sqlite3_malloc", "sqlite3_realloc" },
                    .release_funcs = &[_][]const u8{"sqlite3_free"},
                    .ownership = .caller,
                },
            },
        },

        // ── POSIX ────────────────────────────────────────────────────
        .{
            .name = "posix",
            .description = "POSIX file descriptors and memory mappings",
            .pairs = &[_]AllocPairRule{
                .{
                    .name = "file_descriptor",
                    .alloc_funcs = &[_][]const u8{ "open", "openat", "creat", "socket", "accept", "dup", "fcntl" },
                    .release_funcs = &[_][]const u8{"close"},
                    .ownership = .caller,
                },
                .{
                    .name = "memory_mapping",
                    .alloc_funcs = &[_][]const u8{ "mmap", "mmap64", "shm_open" },
                    .release_funcs = &[_][]const u8{ "munmap", "shm_unlink" },
                    .ownership = .caller,
                },
                .{
                    .name = "directory_stream",
                    .alloc_funcs = &[_][]const u8{"opendir"},
                    .release_funcs = &[_][]const u8{"closedir"},
                    .ownership = .caller,
                },
            },
        },

        // ── GLib ─────────────────────────────────────────────────────
        .{
            .name = "glib",
            .description = "GLib memory management (GNOME/GTK)",
            .pairs = &[_]AllocPairRule{
                .{
                    .name = "memory",
                    .alloc_funcs = &[_][]const u8{ "g_malloc", "g_malloc0", "g_try_malloc", "g_new", "g_new0" },
                    .release_funcs = &[_][]const u8{"g_free"},
                    .ownership = .caller,
                },
                .{
                    .name = "string",
                    .alloc_funcs = &[_][]const u8{ "g_strdup", "g_strndup", "g_build_path", "g_build_filename" },
                    .release_funcs = &[_][]const u8{"g_free"},
                    .ownership = .caller,
                },
            },
        },

        // ── JavaScriptCore (WebKit) ──────────────────────────────────
        .{
            .name = "javascriptcore",
            .description = "WebKit JavaScriptCore GC-managed objects",
            .pairs = &[_]AllocPairRule{},
            .managed_types = &[_]ManagedTypeInfo{
                .{
                    .type_patterns = &[_][]const u8{ "JSObject", "JSString", "JSContextRef", "JSValueRef", "JSPropertyNameArrayRef", "JSObjectMake", "JSStringCreateWithUTF8CString" },
                    .model = .gc,
                    .retain_funcs = &[_][]const u8{ "JSValueProtect", "JSValueRetain", "JSObjectSetPrivate" },
                    .release_funcs = &[_][]const u8{ "JSValueUnprotect" },
                },
            },
        },

        // ── libuv ────────────────────────────────────────────────────
        .{
            .name = "libuv",
            .description = "libuv handles (event loop handles)",
            .pairs = &[_]AllocPairRule{
                .{
                    .name = "tcp",
                    .alloc_funcs = &[_][]const u8{ "uv_tcp_init", "uv_tcp_init_ex" },
                    .release_funcs = &[_][]const u8{"uv_close"},
                    .ownership = .caller,
                },
                .{
                    .name = "timer",
                    .alloc_funcs = &[_][]const u8{"uv_timer_init"},
                    .release_funcs = &[_][]const u8{"uv_close"},
                    .ownership = .caller,
                },
                .{
                    .name = "async_handle",
                    .alloc_funcs = &[_][]const u8{"uv_async_init"},
                    .release_funcs = &[_][]const u8{"uv_close"},
                    .ownership = .caller,
                },
            },
        },

        // ── zlib ──────────────────────────────────────────────────────
        .{
            .name = "zlib",
            .description = "zlib compression stream",
            .pairs = &[_]AllocPairRule{
                .{
                    .name = "stream",
                    .alloc_funcs = &[_][]const u8{ "deflateInit_", "deflateInit2_", "inflateInit_", "inflateInit2_" },
                    .release_funcs = &[_][]const u8{ "deflateEnd", "inflateEnd" },
                    .ownership = .caller,
                },
                .{
                    .name = "gz_file",
                    .alloc_funcs = &[_][]const u8{ "gzopen", "gzdopen", "gzbuffer" },
                    .release_funcs = &[_][]const u8{"gzclose"},
                    .ownership = .caller,
                },
            },
        },

        // ── Python C API ─────────────────────────────────────────────
        .{
            .name = "python_capi",
            .description = "Python C API reference counting",
            .pairs = &[_]AllocPairRule{
                .{
                    .name = "object",
                    .alloc_funcs = &[_][]const u8{ "PyBytes_FromString", "PyBytes_FromStringAndSize", "PyTuple_New", "PyList_New", "PyDict_New" },
                    .release_funcs = &[_][]const u8{ "Py_DECREF", "Py_XDECREF" },
                    .ownership = .caller,
                },
                .{
                    .name = "borrowed_reference",
                    .alloc_funcs = &[_][]const u8{ "PyList_GetItem", "PyDict_GetItem", "PyTuple_GetItem", "PyBytes_AsString" },
                    .release_funcs = &[_][]const u8{},
                    .ownership = .borrowed,
                },
            },
        },

        // ── mimalloc ──────────────────────────────────────────────────
        .{
            .name = "mimalloc",
            .description = "mimalloc - Bun's underlying memory allocator",
            .pairs = &[_]AllocPairRule{
                .{
                    .name = "memory",
                    .alloc_funcs = &[_][]const u8{ "mi_malloc", "mi_zalloc", "mi_realloc", "mi_heap_malloc", "mi_heap_zalloc", "mi_heap_realloc" },
                    .release_funcs = &[_][]const u8{ "mi_free", "mi_heap_free" },
                    .ownership = .caller,
                },
            },
        },
    };
}

/// Check if a function belongs to an error-prone library.
fn libIsErrorProne(db: *const FFIContractDB, func_name: []const u8) bool {
    for (db.libraries) |lib| {
        if (!lib.error_prone) continue;
        for (lib.pairs) |rule| {
            for (rule.alloc_funcs) |pattern| {
                if (matchFuncNameInline(func_name, pattern)) return true;
            }
            for (rule.release_funcs) |pattern| {
                if (matchFuncNameInline(func_name, pattern)) return true;
            }
        }
    }
    return false;
}

/// Inline version of matchFuncName for use in non-method contexts.
fn matchFuncNameInline(haystack: []const u8, needle: []const u8) bool {
    return std.mem.eql(u8, haystack, needle) or
        std.mem.indexOf(u8, haystack, needle) != null;
}

// ============================================================================
// Tests
// ============================================================================

test "shouldReportLeak - OpenSSL SSL_CTX requires manual free" {
    var db = try FFIContractDB.init(std.testing.allocator);
    defer db.deinit();

    // SSL_CTX_new is caller-owned → should report as potential leak
    try std.testing.expect(db.shouldReportLeak("SSL_CTX_new"));
    try std.testing.expect(db.shouldReportLeak("SSL_new"));
    try std.testing.expect(db.shouldReportLeak("BIO_new"));
    try std.testing.expect(db.shouldReportLeak("X509_new"));
}

test "shouldReportLeak - JSC objects are GC managed (suppress FP)" {
    var db = try FFIContractDB.init(std.testing.allocator);
    defer db.deinit();

    // JSObjectMake and friends are GC-managed → should NOT report
    try std.testing.expect(!db.shouldReportLeak("JSObjectMake"));
    try std.testing.expect(!db.shouldReportLeak("JSStringCreateWithUTF8CString"));
    try std.testing.expect(!db.shouldReportLeak("JSValueMakeString"));

    // JSValueProtect/Retain are retains on GC objects → suppress
    try std.testing.expect(!db.shouldReportLeak("JSValueProtect"));
}

test "shouldReportLeak - SQLite requires manual free" {
    var db = try FFIContractDB.init(std.testing.allocator);
    defer db.deinit();

    try std.testing.expect(db.shouldReportLeak("sqlite3_open"));
    try std.testing.expect(db.shouldReportLeak("sqlite3_open_v2"));
    try std.testing.expect(db.shouldReportLeak("sqlite3_prepare_v2"));
}

test "shouldReportLeak - Python borrowed refs are not leaks" {
    var db = try FFIContractDB.init(std.testing.allocator);
    defer db.deinit();

    // PyList_GetItem returns a borrowed ref → do NOT report as leak
    try std.testing.expect(!db.shouldReportLeak("PyList_GetItem"));
    try std.testing.expect(!db.shouldReportLeak("PyDict_GetItem"));
    try std.testing.expect(!db.shouldReportLeak("PyTuple_GetItem"));

    // But PyList_New creates a new object → SHOULD report
    try std.testing.expect(db.shouldReportLeak("PyList_New"));
}

test "shouldReportLeak - unknown function defaults to conservative (report)" {
    var db = try FFIContractDB.init(std.testing.allocator);
    defer db.deinit();

    // Unknown functions conservatively report as potential leak
    try std.testing.expect(db.shouldReportLeak("unknown_custom_alloc"));
    try std.testing.expect(db.shouldReportLeak("my_weird_allocator"));
}

test "isValidRelease - correct pairing for OpenSSL" {
    var db = try FFIContractDB.init(std.testing.allocator);
    defer db.deinit();

    // Valid pairs
    try std.testing.expectEqual(PairMatchResult.valid_pair, db.isValidRelease("SSL_new", "SSL_free"));
    try std.testing.expectEqual(PairMatchResult.valid_pair, db.isValidRelease("SSL_CTX_new", "SSL_CTX_free"));
    try std.testing.expectEqual(PairMatchResult.valid_pair, db.isValidRelease("BIO_new", "BIO_free"));
    try std.testing.expectEqual(PairMatchResult.valid_pair, db.isValidRelease("BIO_new", "BIO_free_all"));
    try std.testing.expectEqual(PairMatchResult.valid_pair, db.isValidRelease("X509_new", "X509_free"));
    try std.testing.expectEqual(PairMatchResult.valid_pair, db.isValidRelease("RSA_new", "RSA_free"));
    try std.testing.expectEqual(PairMatchResult.valid_pair, db.isValidRelease("BN_new", "BN_free"));
}

test "isValidRelease - wrong pairing detection (mismatch)" {
    var db = try FFIContractDB.init(std.testing.allocator);
    defer db.deinit();

    // Mismatch: using wrong release function → potential bug!
    try std.testing.expectEqual(PairMatchResult.mismatch, db.isValidRelease("SSL_new", "BIO_free"));
    try std.testing.expectEqual(PairMatchResult.mismatch, db.isValidRelease("SSL_CTX_new", "SSL_free"));
    try std.testing.expectEqual(PairMatchResult.mismatch, db.isValidRelease("BIO_new", "SSL_free"));
    try std.testing.expectEqual(PairMatchResult.mismatch, db.isValidRelease("X509_new", "free"));
}

test "isValidRelease - correct pairing for SQLite" {
    var db = try FFIContractDB.init(std.testing.allocator);
    defer db.deinit();

    try std.testing.expectEqual(PairMatchResult.valid_pair, db.isValidRelease("sqlite3_open", "sqlite3_close"));
    try std.testing.expectEqual(PairMatchResult.valid_pair, db.isValidRelease("sqlite3_prepare_v2", "sqlite3_finalize"));
    try std.testing.expectEqual(PairMatchResult.mismatch, db.isValidRelease("sqlite3_prepare_v2", "sqlite3_close"));
}

test "isValidRelease - correct pairing for POSIX" {
    var db = try FFIContractDB.init(std.testing.allocator);
    defer db.deinit();

    try std.testing.expectEqual(PairMatchResult.valid_pair, db.isValidRelease("open", "close"));
    try std.testing.expectEqual(PairMatchResult.valid_pair, db.isValidRelease("socket", "close"));
    try std.testing.expectEqual(PairMatchResult.valid_pair, db.isValidRelease("mmap", "munmap"));
}

test "isValidRelease - unknown alloc function" {
    var db = try FFIContractDB.init(std.testing.allocator);
    defer db.deinit();

    try std.testing.expectEqual(PairMatchResult.unknown_alloc, db.isValidRelease("unknown_func", "free"));
}

test "getExpectedReleases - returns valid release functions" {
    var db = try FFIContractDB.init(std.testing.allocator);
    defer db.deinit();

    const ssl_releases = db.getExpectedReleases("SSL_new");
    try std.testing.expect(ssl_releases != null);
    if (ssl_releases) |releases| {
        // Should contain SSL_free
        var found = false;
        for (releases) |r| {
            if (std.mem.eql(u8, r, "SSL_free")) {
                found = true;
                break;
            }
        }
        try std.testing.expect(found);
    }

    const sqlite_releases = db.getExpectedReleases("sqlite3_prepare_v2");
    try std.testing.expect(sqlite_releases != null);
    if (sqlite_releases) |releases| {
        var found = false;
        for (releases) |r| {
            if (std.mem.eql(u8, r, "sqlite3_finalize")) {
                found = true;
                break;
            }
        }
        try std.testing.expect(found);
    }

    // Unknown function → null
    try std.testing.expect(db.getExpectedReleases("unknown_func") == null);
}

test "getOwnership - returns correct ownership model" {
    var db = try FFIContractDB.init(std.testing.allocator);
    defer db.deinit();

    try std.testing.expectEqual(OwnershipModel.caller, db.getOwnership("SSL_CTX_new").?);
    try std.testing.expectEqual(OwnershipModel.caller, db.getOwnership("sqlite3_open").?);
    try std.testing.expectEqual(OwnershipModel.gc, db.getOwnership("JSObjectMake").?);
    try std.testing.expectEqual(OwnershipModel.borrowed, db.getOwnership("PyList_GetItem").?);

    // Unknown
    try std.testing.expect(db.getOwnership("unknown") == null);
}

test "isErrorProneLib - identifies error-prone libraries" {
    var db = try FFIContractDB.init(std.testing.allocator);
    defer db.deinit();

    // OpenSSL and SQLite are marked error-prone
    try std.testing.expect(db.isErrorProneLib("SSL_CTX_new"));
    try std.testing.expect(db.isErrorProneLib("SSL_free"));
    try std.testing.expect(db.isErrorProneLib("sqlite3_open"));
    try std.testing.expect(db.isErrorProneLib("sqlite3_finalize"));

    // GLib is NOT marked error-prone
    try std.testing.expect(!db.isErrorProneLib("g_malloc"));
    try std.testing.expect(!db.isErrorProneLib("g_free"));
}

test "findRuleForAlloc - locates correct rule" {
    var db = try FFIContractDB.init(std.testing.allocator);
    defer db.deinit();

    const rule = db.findRuleForAlloc("EVP_CIPHER_CTX_new");
    try std.testing.expect(rule != null);
    if (rule) |r| {
        try std.testing.expectEqualStrings("EVP_CIPHER_CTX", r.name);
        try std.testing.expectEqual(OwnershipModel.caller, r.ownership);
    }
}

test "substring matching - TLS_method matches SSL_CTX rule" {
    var db = try FFIContractDB.init(std.testing.allocator);
    defer db.deinit();

    // TLS_method is listed as an alloc func for SSL_CTX
    try std.testing.expect(db.shouldReportLeak("TLS_method"));
    try std.testing.expectEqual(PairMatchResult.valid_pair, db.isValidRelease("TLS_method", "SSL_CTX_free"));
}

test "builtinLibraries - all libraries have required fields" {
    const libs = builtinLibraries();
    try std.testing.expect(libs.len > 0);

    for (libs) |lib| {
        // Every library must have a name
        try std.testing.expect(lib.name.len > 0);

        // Pairs can be empty (e.g., javascriptcore only has managed_types)
        for (lib.pairs) |pair| {
            try std.testing.expect(pair.name.len > 0);
            try std.testing.expect(pair.alloc_funcs.len > 0);
            try std.testing.expect(pair.release_funcs.len > 0);
        }
    }
}

test "mimalloc rules - Bun's underlying allocator" {
    var db = try FFIContractDB.init(std.testing.allocator);
    defer db.deinit();

    try std.testing.expect(db.shouldReportLeak("mi_malloc"));
    try std.testing.expect(db.shouldReportLeak("mi_zalloc"));
    try std.testing.expectEqual(PairMatchResult.valid_pair, db.isValidRelease("mi_malloc", "mi_free"));
    try std.testing.expectEqual(PairMatchResult.mismatch, db.isValidRelease("mi_malloc", "free"));
}

test "zlib rules - deflate/inflate streams" {
    var db = try FFIContractDB.init(std.testing.allocator);
    defer db.deinit();

    try std.testing.expectEqual(PairMatchResult.valid_pair, db.isValidRelease("deflateInit_", "deflateEnd"));
    try std.testing.expectEqual(PairMatchResult.valid_pair, db.isValidRelease("inflateInit_", "inflateEnd"));
    try std.testing.expectEqual(PairMatchResult.mismatch, db.isValidRelease("deflateInit_", "free"));
}
