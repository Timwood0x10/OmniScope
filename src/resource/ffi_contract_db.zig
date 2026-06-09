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
const jni_reg = @import("../registry/jni_reg.zig");
const cdb_data = @import("ffi_contract_db_data.zig");

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
    stats: Stats,

    /// Statistics for contract database usage tracking
    pub const Stats = struct {
        shouldReportLeak_calls: u32 = 0,
        isValidRelease_calls: u32 = 0,
        getExpectedReleases_calls: u32 = 0,
        getOwnership_calls: u32 = 0,
        isErrorProneLib_calls: u32 = 0,
        mismatch_count: u32 = 0,
        cache_hits: u32 = 0,
    };

    /// Initialize the contract database with built-in rules.
    /// No file I/O needed — all data is embedded at compile time.
    pub fn init(_: std.mem.Allocator) !FFIContractDB {
        return .{
            .allocator = undefined,
            .libraries = cdb_data.builtinLibraries(),
            .stats = .{},
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
    pub fn shouldReportLeak(self: *FFIContractDB, alloc_func: []const u8) bool {
        self.stats.shouldReportLeak_calls += 1;
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
        self: *FFIContractDB,
        alloc_func: []const u8,
        release_func: []const u8,
    ) PairMatchResult {
        self.stats.isValidRelease_calls += 1;
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
        self.stats.mismatch_count += 1;
        return .mismatch;
    }

    /// Get the correct release function(s) for an allocation function.
    ///
    /// Returns null if the allocation function is unknown.
    pub fn getExpectedReleases(
        self: *FFIContractDB,
        alloc_func: []const u8,
    ) ?[]const []const u8 {
        self.stats.getExpectedReleases_calls += 1;
        const rule = self.findRuleForAlloc(alloc_func) orelse return null;
        return rule.release_funcs;
    }

    /// Get the ownership model for an allocation function.
    ///
    /// Returns null if the function is unknown.
    pub fn getOwnership(
        self: *FFIContractDB,
        func_name: []const u8,
    ) ?OwnershipModel {
        self.stats.getOwnership_calls += 1;
        const rule = self.findRuleForAlloc(func_name) orelse return null;
        return rule.ownership;
    }

    /// Get the ownership model for a managed type (GC/refcount/RAII).
    ///
    /// Searches both alloc_pairs and managed_types. This is needed because
    /// some functions (like JSObjectMake) are only in managed_types, not in pairs.
    pub fn getOwnershipManaged(self: *FFIContractDB, func_name: []const u8) ?OwnershipModel {
        self.stats.getOwnership_calls += 1;

        // First try normal alloc pairs (fast path)
        if (self.findRuleForAlloc(func_name)) |rule| {
            return rule.ownership;
        }

        // Then search managed_types (for GC-managed objects like JSObjectMake)
        for (self.libraries) |lib| {
            if (lib.managed_types) |mts| {
                for (mts) |mt| {
                    for (mt.type_patterns) |pattern| {
                        if (matchFuncName(func_name, pattern)) {
                            return mt.model;
                        }
                    }
                }
            }
        }

        return null;
    }

    /// Get confidence score for a rule by allocation function name.
    ///
    /// Returns the confidence (0.0–1.0) for the matching rule.
    /// Returns 0.5 (medium confidence) if function is unknown.
    pub fn getConfidence(self: *FFIContractDB, alloc_func: []const u8) f32 {
        const rule = self.findRuleForAlloc(alloc_func) orelse return 0.5;
        return rule.confidence;
    }

    /// Get total number of libraries in the database.
    pub fn libraryCount(self: *const FFIContractDB) usize {
        return self.libraries.len;
    }

    /// Get total number of rules across all libraries.
    pub fn totalRules(self: *const FFIContractDB) usize {
        var count: usize = 0;
        for (self.libraries) |lib| {
            count += lib.pairs.len;
        }
        return count;
    }

    /// Is this function from a historically error-prone library?
    ///
    /// Used to boost confidence/score for issues involving these libraries.
    pub fn isErrorProneLib(self: *FFIContractDB, func_name: []const u8) bool {
        self.stats.isErrorProneLib_calls += 1;
        return libIsErrorProne(self, func_name);
    }

    /// Get all known allocation function names across all libraries.
    /// NOTE: Currently unimplemented — returns empty slice. Callers should
    /// use `isKnownAllocator()` for per-function checks, or iterate
    /// `self.libraries[].pairs[].alloc_funcs` directly if a full list is needed.
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

    /// Check if a function name is a known library allocator in the contract DB.
    ///
    /// Returns true if the function appears as an allocation function in any
    /// AllocPairRule (e.g., sqlite3_open, SSL_CTX_new, BIO_new, deflateInit_).
    /// Used by trackPointerOrigin to decide whether to record pointer origin
    /// entries for contract-based release validation.
    pub fn isKnownAllocator(self: *const FFIContractDB, func_name: []const u8) bool {
        return self.findRuleForAlloc(func_name) != null;
    }

    /// Print usage statistics for the contract database.
    /// Call this at the end of analysis to see how the DB was used.
    pub fn printStats(self: *FFIContractDB) void {
        log.info("FFIContractDB Stats: libraries={}, rules={}, queries={}", .{
            self.libraries.len,
            self.totalRules(),
            self.stats.shouldReportLeak_calls + self.stats.isValidRelease_calls +
                self.stats.getExpectedReleases_calls + self.stats.getOwnership_calls +
                self.stats.isErrorProneLib_calls,
        });
    }

    // ── Helpers ──

    /// Match a function name against a pattern.
    /// Supports exact match and substring containment.
    fn matchFuncName(haystack: []const u8, needle: []const u8) bool {
        return std.mem.eql(u8, haystack, needle) or
            std.mem.indexOf(u8, haystack, needle) != null;
    }
};

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
