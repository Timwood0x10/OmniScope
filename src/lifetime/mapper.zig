//! Semantic Mapper
//!
//! Maps LLVM IR function calls to semantic actions for the Lifetime Engine.
//!
//! This is the "Language Frontend" layer that recognizes:
//! - malloc/free (C)
//! - Box::into_raw/from_raw (Rust)
//! - allocator.alloc (Zig)
//! - UnsafeMutablePointer.allocate (Swift)
//!
//! The mapper is language-agnostic - it only cares about the SEMANTIC MEANING
//! of the function, not the syntax.
//!
//! Key Design Principle:
//! - Data-driven rules, NOT if-else hell
//! - 90% of lifetime semantics happen at function calls
//! - Only care about actions that change resource lifetime state

const std = @import("std");
const engine = @import("engine.zig");

pub const SemanticAction = engine.SemanticAction;
pub const Owner = engine.Owner;
pub const LanguageHint = engine.LanguageHint;

/// A mapped semantic action from an LLVM IR instruction.
pub const MappedAction = struct {
    /// The semantic action detected.
    action: SemanticAction,
    /// The resource ID involved (if applicable).
    resource_id: ?u64,
    /// Language hint for diagnostics.
    lang_hint: LanguageHint,
    /// Function name that triggered this action.
    trigger_fn: []const u8,
    /// Argument index that holds the resource (if applicable).
    arg_index: ?u8,
    /// Whether this action returns a new resource.
    returns_resource: bool,
    /// Human-readable description.
    description: []const u8,
};

/// Function semantic mapping rule.
/// Data-driven rule for mapping function calls to semantic actions.
///
/// This is the core of the semantic mapper - all rules are data,
/// not code. Adding new language support means adding new rules,
/// not writing new if-else branches.
pub const Rule = struct {
    /// Pattern to match function name.
    symbol_pattern: []const u8,
    /// Match type (exact, contains, suffix).
    match_type: MatchType,
    /// The semantic action this function performs.
    action: SemanticAction,
    /// Language hint for diagnostics.
    lang_hint: LanguageHint,
    /// Argument index that holds the resource (0-based).
    /// null if the action doesn't take a resource argument.
    arg_index: ?u8 = null,
    /// Whether this function returns a new resource.
    returns_resource: bool = false,
    /// Human-readable description for diagnostics.
    description: []const u8,
};

/// Match type for function patterns.
pub const MatchType = enum {
    /// Exact name match.
    exact,
    /// Pattern appears anywhere in the name.
    contains,
    /// Name ends with the pattern.
    suffix,
};

/// The semantic function database.
/// Maps function names to semantic actions.
///
/// This is the single source of truth for all semantic mappings.
/// Adding new language support = adding new rules here.
pub const RULES = [_]Rule{
    // === C Standard Library ===
    // alloc: returns new resource
    .{
        .symbol_pattern = "malloc",
        .match_type = .exact,
        .action = .alloc,
        .lang_hint = .c,
        .arg_index = null,
        .returns_resource = true,
        .description = "C heap allocation",
    },
    .{
        .symbol_pattern = "calloc",
        .match_type = .exact,
        .action = .alloc,
        .lang_hint = .c,
        .arg_index = null,
        .returns_resource = true,
        .description = "C zeroed heap allocation",
    },
    .{
        .symbol_pattern = "realloc",
        .match_type = .exact,
        .action = .alloc,
        .lang_hint = .c,
        .arg_index = 0,
        .returns_resource = true,
        .description = "C reallocation (consumes old, returns new)",
    },
    // free: consumes resource at arg 0
    .{
        .symbol_pattern = "free",
        .match_type = .exact,
        .action = .free,
        .lang_hint = .c,
        .arg_index = 0,
        .returns_resource = false,
        .description = "C heap deallocation",
    },

    // === Rust Ownership ===
    // transfer: ownership OUT of Rust (arg 0)
    .{
        .symbol_pattern = "into_raw",
        .match_type = .contains,
        .action = .transfer,
        .lang_hint = .rust,
        .arg_index = 0,
        .returns_resource = true,
        .description = "Rust ownership transfer OUT (Box::into_raw, CString::into_raw)",
    },
    // reclaim: ownership INTO Rust (arg 0)
    .{
        .symbol_pattern = "from_raw",
        .match_type = .contains,
        .action = .reclaim,
        .lang_hint = .rust,
        .arg_index = 0,
        .returns_resource = true,
        .description = "Rust ownership transfer IN (Box::from_raw, CString::from_raw)",
    },
    // borrow: pointer without ownership transfer
    .{
        .symbol_pattern = "as_ptr",
        .match_type = .contains,
        .action = .borrow,
        .lang_hint = .rust,
        .arg_index = 0,
        .returns_resource = true,
        .description = "Rust borrow escape (&str.as_ptr, slice.as_ptr)",
    },
    .{
        .symbol_pattern = "as_mut_ptr",
        .match_type = .contains,
        .action = .borrow,
        .lang_hint = .rust,
        .arg_index = 0,
        .returns_resource = true,
        .description = "Rust mutable borrow escape",
    },

    // === Go cgo (must be before Zig to match C.malloc before alloc) ===
    // alloc: C.malloc in cgo
    .{
        .symbol_pattern = "C.malloc",
        .match_type = .contains,
        .action = .alloc,
        .lang_hint = .go,
        .arg_index = null,
        .returns_resource = true,
        .description = "Go cgo C memory allocation",
    },
    // free: C.free in cgo
    .{
        .symbol_pattern = "C.free",
        .match_type = .contains,
        .action = .free,
        .lang_hint = .go,
        .arg_index = 0,
        .returns_resource = false,
        .description = "Go cgo C memory deallocation",
    },
    // alloc: C.CString allocates C string (must be freed by C.free)
    .{
        .symbol_pattern = "C.CString",
        .match_type = .contains,
        .action = .alloc,
        .lang_hint = .go,
        .arg_index = null,
        .returns_resource = true,
        .description = "Go cgo CString allocation (needs C.free)",
    },
    // borrow: C.GoString borrows C string (no ownership transfer)
    .{
        .symbol_pattern = "C.GoString",
        .match_type = .contains,
        .action = .borrow,
        .lang_hint = .go,
        .arg_index = 0,
        .returns_resource = false,
        .description = "Go cgo GoString borrow (copies, no ownership)",
    },
    // borrow: C.GoBytes borrows C bytes
    .{
        .symbol_pattern = "C.GoBytes",
        .match_type = .contains,
        .action = .borrow,
        .lang_hint = .go,
        .arg_index = 0,
        .returns_resource = false,
        .description = "Go cgo GoBytes borrow (copies, no ownership)",
    },

    // === Zig Allocator ===
    // alloc: returns new resource
    .{
        .symbol_pattern = "alloc",
        .match_type = .contains,
        .action = .alloc,
        .lang_hint = .zig,
        .arg_index = null,
        .returns_resource = true,
        .description = "Zig allocator allocation",
    },
    // free: consumes resource
    .{
        .symbol_pattern = "destroy",
        .match_type = .contains,
        .action = .free,
        .lang_hint = .zig,
        .arg_index = 0,
        .returns_resource = false,
        .description = "Zig allocator deallocation",
    },
    // free: resize/shrink (may consume)
    .{
        .symbol_pattern = "resize",
        .match_type = .contains,
        .action = .free,
        .lang_hint = .zig,
        .arg_index = 0,
        .returns_resource = false,
        .description = "Zig allocator resize (may free)",
    },
    // transfer: toOwnedSlice transfers ownership
    .{
        .symbol_pattern = "toOwnedSlice",
        .match_type = .contains,
        .action = .transfer,
        .lang_hint = .zig,
        .arg_index = 0,
        .returns_resource = true,
        .description = "Zig ArrayList ownership transfer",
    },
    // alloc: dupe creates new owned memory
    .{
        .symbol_pattern = "dupe",
        .match_type = .contains,
        .action = .alloc,
        .lang_hint = .zig,
        .arg_index = null,
        .returns_resource = true,
        .description = "Zig allocator duplicate",
    },

    // === Swift Unsafe ===
    // alloc: returns new resource
    .{
        .symbol_pattern = "allocate",
        .match_type = .contains,
        .action = .alloc,
        .lang_hint = .swift,
        .arg_index = null,
        .returns_resource = true,
        .description = "Swift UnsafeMutablePointer allocation",
    },
    // free: consumes resource
    .{
        .symbol_pattern = "deallocate",
        .match_type = .contains,
        .action = .free,
        .lang_hint = .swift,
        .arg_index = 0,
        .returns_resource = false,
        .description = "Swift UnsafeMutablePointer deallocation",
    },

    // === C++ (via extern "C") ===
    // alloc: returns new resource
    .{
        .symbol_pattern = "operator new",
        .match_type = .contains,
        .action = .alloc,
        .lang_hint = .cpp,
        .arg_index = null,
        .returns_resource = true,
        .description = "C++ heap allocation",
    },
    // free: consumes resource
    .{
        .symbol_pattern = "operator delete",
        .match_type = .contains,
        .action = .free,
        .lang_hint = .cpp,
        .arg_index = 0,
        .returns_resource = false,
        .description = "C++ heap deallocation",
    },
};

/// The Semantic Mapper.
/// Maps LLVM IR function calls to semantic actions.
pub const SemanticMapper = struct {
    /// Map a function name to its semantic action.
    /// Returns null if the function is not recognized.
    pub fn mapFunction(func_name: []const u8) ?MappedAction {
        for (RULES) |rule| {
            if (matchesPattern(func_name, rule.symbol_pattern, rule.match_type)) {
                return .{
                    .action = rule.action,
                    .resource_id = null,
                    .lang_hint = rule.lang_hint,
                    .trigger_fn = func_name,
                    .arg_index = rule.arg_index,
                    .returns_resource = rule.returns_resource,
                    .description = rule.description,
                };
            }
        }
        return null;
    }

    /// Check if a function performs a specific semantic action.
    pub fn isAction(func_name: []const u8, action: SemanticAction) bool {
        const mapped = mapFunction(func_name) orelse return false;
        return mapped.action == action;
    }

    /// Check if a function is an allocation.
    pub fn isAllocation(func_name: []const u8) bool {
        return isAction(func_name, .alloc);
    }

    /// Check if a function is a deallocation.
    pub fn isDeallocation(func_name: []const u8) bool {
        return isAction(func_name, .free);
    }

    /// Check if a function transfers ownership.
    pub fn isTransfer(func_name: []const u8) bool {
        return isAction(func_name, .transfer);
    }

    /// Check if a function reclaims ownership.
    pub fn isReclaim(func_name: []const u8) bool {
        return isAction(func_name, .reclaim);
    }

    /// Check if a function borrows a resource.
    pub fn isBorrow(func_name: []const u8) bool {
        return isAction(func_name, .borrow);
    }

    /// Get the language hint for a function.
    pub fn getLanguageHint(func_name: []const u8) LanguageHint {
        const mapped = mapFunction(func_name) orelse return .unknown;
        return mapped.lang_hint;
    }

    /// Get the description for a function.
    pub fn getDescription(func_name: []const u8) ?[]const u8 {
        for (RULES) |rule| {
            if (matchesPattern(func_name, rule.symbol_pattern, rule.match_type)) {
                return rule.description;
            }
        }
        return null;
    }

    /// Get the count of known semantic mappings.
    pub fn ruleCount() usize {
        return RULES.len;
    }
};

/// Check if a function name matches a pattern.
fn matchesPattern(func_name: []const u8, pattern: []const u8, match_type: MatchType) bool {
    return switch (match_type) {
        .exact => std.mem.eql(u8, func_name, pattern),
        .contains => std.mem.indexOf(u8, func_name, pattern) != null,
        .suffix => std.mem.endsWith(u8, func_name, pattern),
    };
}

// Unit tests

test "SemanticMapper - mapFunction malloc" {
    const mapped = SemanticMapper.mapFunction("malloc").?;
    try std.testing.expectEqual(SemanticAction.alloc, mapped.action);
    try std.testing.expectEqual(LanguageHint.c, mapped.lang_hint);
}

test "SemanticMapper - mapFunction free" {
    const mapped = SemanticMapper.mapFunction("free").?;
    try std.testing.expectEqual(SemanticAction.free, mapped.action);
    try std.testing.expectEqual(LanguageHint.c, mapped.lang_hint);
}

test "SemanticMapper - mapFunction into_raw" {
    const mapped = SemanticMapper.mapFunction("std::boxed::Box<T>::into_raw").?;
    try std.testing.expectEqual(SemanticAction.transfer, mapped.action);
    try std.testing.expectEqual(LanguageHint.rust, mapped.lang_hint);
}

test "SemanticMapper - mapFunction from_raw" {
    const mapped = SemanticMapper.mapFunction("std::boxed::Box<T>::from_raw").?;
    try std.testing.expectEqual(SemanticAction.reclaim, mapped.action);
    try std.testing.expectEqual(LanguageHint.rust, mapped.lang_hint);
}

test "SemanticMapper - mapFunction as_ptr" {
    const mapped = SemanticMapper.mapFunction("slice.as_ptr").?;
    try std.testing.expectEqual(SemanticAction.borrow, mapped.action);
    try std.testing.expectEqual(LanguageHint.rust, mapped.lang_hint);
}

test "SemanticMapper - mapFunction unknown" {
    try std.testing.expect(SemanticMapper.mapFunction("unknown_func") == null);
}

test "SemanticMapper - isAllocation" {
    try std.testing.expect(SemanticMapper.isAllocation("malloc"));
    try std.testing.expect(SemanticMapper.isAllocation("calloc"));
    try std.testing.expect(!SemanticMapper.isAllocation("free"));
}

test "SemanticMapper - isDeallocation" {
    try std.testing.expect(SemanticMapper.isDeallocation("free"));
    try std.testing.expect(!SemanticMapper.isDeallocation("malloc"));
}

test "SemanticMapper - isTransfer" {
    try std.testing.expect(SemanticMapper.isTransfer("into_raw"));
    try std.testing.expect(!SemanticMapper.isTransfer("from_raw"));
}

test "SemanticMapper - isReclaim" {
    try std.testing.expect(SemanticMapper.isReclaim("from_raw"));
    try std.testing.expect(!SemanticMapper.isReclaim("into_raw"));
}

test "SemanticMapper - isBorrow" {
    try std.testing.expect(SemanticMapper.isBorrow("as_ptr"));
    try std.testing.expect(SemanticMapper.isBorrow("as_mut_ptr"));
    try std.testing.expect(!SemanticMapper.isBorrow("malloc"));
}

test "SemanticMapper - getLanguageHint" {
    try std.testing.expectEqual(LanguageHint.c, SemanticMapper.getLanguageHint("malloc"));
    try std.testing.expectEqual(LanguageHint.rust, SemanticMapper.getLanguageHint("into_raw"));
    try std.testing.expectEqual(LanguageHint.unknown, SemanticMapper.getLanguageHint("unknown"));
}

test "SemanticMapper - getDescription" {
    const desc = SemanticMapper.getDescription("malloc").?;
    try std.testing.expect(std.mem.indexOf(u8, desc, "allocation") != null);
}

test "SemanticMapper - ruleCount" {
    try std.testing.expect(SemanticMapper.ruleCount() >= 12);
}

test "matchesPattern" {
    try std.testing.expect(matchesPattern("malloc", "malloc", .exact));
    try std.testing.expect(!matchesPattern("malloc2", "malloc", .exact));
    try std.testing.expect(matchesPattern("std::into_raw", "into_raw", .contains));
    try std.testing.expect(matchesPattern("_system", "system", .suffix));
}
