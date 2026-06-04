//! Language Override Integration Tests
//!
//! Thorough unit tests covering the LanguageOverrideRegistry public API.
//! Tests the registry lookup priority chain, JSON loading, CLI merging,
//! edge cases, and memory safety.

const std = @import("std");
const language_override = @import("../src/config/language_override.zig");

const LanguageOverrideRegistry = language_override.LanguageOverrideRegistry;
const Language = language_override.Language;

// ── Test 1: Registry lookup priority chain (exact > prefix > suffix > null) ──

test "priority chain: exact match beats prefix and suffix" {
    const alloc = std.testing.allocator;
    var reg = try LanguageOverrideRegistry.init(alloc);
    defer reg.deinit();

    // Set up: same name could match exact, prefix, AND suffix
    try reg.addExact("special_func", .java);
    try reg.addPrefix("special_", .go);
    try reg.addSuffix("_func", .rust);
    reg.sortPrefixRules();
    reg.sortSuffixRules();

    // Exact should always win (priority #1)
    try std.testing.expectEqual(.java, reg.lookup("special_func").?);

    // Name matching prefix but NOT exact → prefix (priority #2)
    try std.testing.expectEqual(.go, reg.lookup("special_other").?);

    // Name matching only suffix → suffix (priority #3)
    try std.testing.expectEqual(.rust, reg.lookup("other_func").?);

    // No match at all → null (caller uses auto-detection)
    try std.testing.expect(reg.lookup("completely_unknown") == null);
}

// ── Test 2: Longest prefix wins ──

test "longest prefix wins: sqlite3_ beats sql_" {
    const alloc = std.testing.allocator;
    var reg = try LanguageOverrideRegistry.init(alloc);
    defer reg.deinit();

    // Add in arbitrary order — sort should fix it
    try reg.addPrefix("sql_", .c);
    try reg.addPrefix("sqlite3_", .c);
    try reg.addPrefix("sqlite3_open_", .c);
    reg.sortPrefixRules();

    // Longest matching prefix should win
    try std.testing.expectEqual(.c, reg.lookup("sqlite3_open_db_v2").?); // matches sqlite3_open_
    try std.testing.expectEqual(.c, reg.lookup("sqlite3_exec").?); // matches sqlite3_
    try std.testing.expectEqual(.c, reg.lookup("sql_database").?); // matches sql_

    // No prefix match
    try std.testing.expect(reg.lookup("malloc") == null);
}

// ── Test 3: parseLangString with aliases ──

test "parseLangString: standard names" {
    try std.testing.expectEqual(.c, LanguageOverrideRegistry.parseLangString("c").?);
    try std.testing.expectEqual(.cpp, LanguageOverrideRegistry.parseLangString("cpp").?);
    try std.testing.expectEqual(.rust, LanguageOverrideRegistry.parseLangString("rust").?);
    try std.testing.expectEqual(.zig, LanguageOverrideRegistry.parseLangString("zig").?);
    try std.testing.expectEqual(.go, LanguageOverrideRegistry.parseLangString("go").?);
    try std.testing.expectEqual(.python, LanguageOverrideRegistry.parseLangString("python").?);
    try std.testing.expectEqual(.java, LanguageOverrideRegistry.parseLangString("java").?);
    try std.testing.expectEqual(.csharp, LanguageOverrideRegistry.parseLangString("csharp").?);
    try std.testing.expectEqual(.unknown, LanguageOverrideRegistry.parseLangString("unknown").?);
}

test "parseLangString: aliases (c++, py, c#)" {
    // C++ alias
    try std.testing.expectEqual(.cpp, LanguageOverrideRegistry.parseLangString("c++").?);

    // Python alias
    try std.testing.expectEqual(.python, LanguageOverrideRegistry.parseLangString("py").?);

    // C# alias
    try std.testing.expectEqual(.csharp, LanguageOverrideRegistry.parseLangString("c#").?);
}

test "parseLangString: invalid values return null" {
    try std.testing.expect(LanguageOverrideRegistry.parseLangString("") == null);
    try std.testing.expect(LanguageOverrideRegistry.parseLangString("invalid") == null);
    try std.testing.expect(LanguageOverrideRegistry.parseLangString("C") == null); // case-sensitive
    try std.testing.expect(LanguageOverrideRegistry.parseLangString("Rust") == null);
    try std.testing.expect(LanguageOverrideRegistry.parseLangString("CPlusPlus") == null);
}

// ── Test 4: loadFromJson with full overrides JSON ──

test "loadFromJson: full overrides JSON" {
    const alloc = std.testing.allocator;
    var reg = try LanguageOverrideRegistry.init(alloc);
    defer reg.deinit();

    const json =
        \\{
        \\  "exact": {
        \\    "__rust_alloc": "rust",
        \\    "__rust_dealloc": "rust",
        \\    "malloc": "c"
        \\  },
        \\  "prefix": {
        \\    "sqlite3_": "c",
        \\    "PyInit_": "python",
        \\    "_ZN": "rust"
        \\  },
        \\  "suffix": {
        \\    "_rs": "rust",
        \\    "_vtable": "c"
        \\  },
        \\  "source_files": {
        \\    "generated.ll": "c",
        \\    "wrapper.go": "go"
        \\  },
        \\  "default_language": "zig"
        \\
    ;
    try reg.loadFromJson(json);

    // Verify exact matches
    try std.testing.expectEqual(.rust, reg.lookup("__rust_alloc").?);
    try std.testing.expectEqual(.rust, reg.lookup("__rust_dealloc").?);
    try std.testing.expectEqual(.c, reg.lookup("malloc").?);

    // Verify prefix matches
    try std.testing.expectEqual(.c, reg.lookup("sqlite3_open").?);
    try std.testing.expectEqual(.python, reg.lookup("PyInit_foo").?);
    try std.testing.expectEqual(.rust, reg.lookup("ZN5alloc5boxed19Box...")); // mangled Rust

    // Verify suffix matches
    try std.testing.expectEqual(.rust, reg.lookup("my_function_rs").?);
    try std.testing.expectEqual(.c, reg.lookup("my_class_vtable").?);

    // Verify source file lookups
    try std.testing.expectEqual(.c, reg.lookupSourceFile("generated.ll").?);
    try std.testing.expectEqual(.c, reg.lookupSourceFile("./generated.ll").?); // basename match
    try std.testing.expectEqual(.go, reg.lookupSourceFile("wrapper.go").?);

    // Verify default language
    try std.testing.expectEqual(.zig, reg.getDefault().?);
}

test "loadFromJson: empty / minimal JSON" {
    const alloc = std.testing.allocator;

    // Empty object → no errors, empty registry
    var reg1 = try LanguageOverrideRegistry.init(alloc);
    defer reg1.deinit();
    try reg1.loadFromJson("{}");
    try std.testing.expect(reg1.isEmpty());

    // Only one section populated
    var reg2 = try LanguageOverrideRegistry.init(alloc);
    defer reg2.deinit();
    try reg2.loadFromJson(
        \\"exact": {"only_one": "c"}
        \\
    );
    try std.testing.expectEqual(.c, reg2.lookup("only_one").?);
    try std.testing.expect(reg2.lookup("other") == null);
}

test "loadFromJson: ignores unknown languages gracefully" {
    const alloc = std.testing.allocator;
    var reg = try LanguageOverrideRegistry.init(alloc);
    defer reg.deinit();

    // Unknown language strings are skipped silently
    try reg.loadFromJson(
        \\"exact": {"valid": "c", "invalid_lang": "foobar", "also_bad": "123"}
        \\
    );
    try std.testing.expectEqual(.c, reg.lookup("valid").?);
    // Invalid entries were skipped — registry has only 1 entry
    try std.testing.expect(reg.lookup("invalid_lang") == null);
    try std.testing.expect(reg.lookup("also_bad") == null);
}

// ── Test 5: mergeFromCLI overwrites exact entries (no memory leak) ──

test "mergeFromCLI: CLI overwrites JSON exact entries" {
    const alloc = std.testing.allocator;
    var reg = try LanguageOverrideRegistry.init(alloc);
    defer reg.deinit();

    // Simulate: JSON config loaded first
    try reg.addExact("malloc", .c);
    try reg.addExact("__rust_alloc", .rust);
    try reg.addPrefix("py_", .python);
    reg.sortPrefixRules();

    // Then CLI args applied — CLI takes priority
    const cli = LanguageOverrideRegistry.CLIOverrides{
        .exact = &.{.{ "malloc", "rust" }}, // Overwrite malloc from c→rust!
        .prefix = &.{.{ "go_", "go" }},
        .suffix = &.{.{ "_rs", "rust" }},
        .source_files = &.{.{ "gen.ll", "c" }},
        .default_lang = "zig",
    };
    try reg.mergeFromCLI(cli);

    // CLI exact overwrote JSON value
    try std.testing.expectEqual(.rust, reg.lookup("malloc").?);

    // Original non-conflicting entries preserved
    try std.testing.expectEqual(.rust, reg.lookup("__rust_alloc").?);
    try std.testing.expectEqual(.python, reg.lookup("py_something").?);

    // New CLI-only entries added
    try std.testing.expectEqual(.go, reg.lookup("go_runtime").?);
    try std.testing.expectEqual(.rust, reg.lookup("something_rs").?);
    try std.testing.expectEqual(.c, reg.lookupSourceFile("gen.ll").?);

    // Default language from CLI
    try std.testing.expectEqual(.zig, reg.getDefault().?);
}

test "mergeFromCLI: idempotent overwrite does not leak" {
    const alloc = std.testing.allocator;
    var reg = try LanguageOverrideRegistry.init(alloc);
    defer reg.deinit();

    // Pre-populate
    try reg.addExact("key1", .c);
    try reg.addExact("key2", .rust);

    // Overwrite key1 twice — should not leak memory
    const cli1 = LanguageOverrideRegistry.CLIOverrides{
        .exact = &.{.{ "key1", "cpp" }},
        .prefix = &.{},
        .suffix = &.{},
        .source_files = &.{},
        .default_lang = null,
    };
    try reg.mergeFromCLI(cli1);
    try std.testing.expectEqual(.cpp, reg.lookup("key1").?);

    const cli2 = LanguageOverrideRegistry.CLIOverrides{
        .exact = &.{.{ "key1", "java" }}, // overwrite again
        .prefix = &.{},
        .suffix = &.{},
        .source_files = &.{},
        .default_lang = null,
    };
    try reg.mergeFromCLI(cli2);
    try std.testing.expectEqual(.java, reg.lookup("key1").?);

    // key2 untouched
    try std.testing.expectEqual(.rust, reg.lookup("key2").?);
}

// ── Test 6: addSourceFile with basename matching ──

test "addSourceFile: basename matching works" {
    const alloc = std.testing.allocator;
    var reg = try LanguageOverrideRegistry.init(alloc);
    defer reg.deinit();

    try reg.addSourceFile("generated.ll", .c);
    try reg.addSourceFile("/deep/path/to/module.bc", .rust);

    // Basename match
    try std.testing.expectEqual(.c, reg.lookupSourceFile("generated.ll").?);
    try std.testing.expectEqual(.c, reg.lookupSourceFile("./generated.ll").?);
    try std.testing.expectEqual(.c, reg.lookupSourceFile("/any/path/generated.ll").?);

    // Full path match (no basename conflict)
    try std.testing.expectEqual(.rust, reg.lookupSourceFile("/deep/path/to/module.bc").?);

    // Not found
    try std.testing.expect(reg.lookupSourceFile("unknown_file.zig") == null);
}

test "addSourceFile: overwrite existing entry frees old key" {
    const alloc = std.testing.allocator;
    var reg = try LanguageOverrideRegistry.init(alloc);
    defer reg.deinit();

    try reg.addSourceFile("test.ll", .c);
    try std.testing.expectEqual(.c, reg.lookupSourceFile("test.ll").?);

    // Overwrite same basename — should not leak
    try reg.addSourceFile("test.ll", .rust);
    try std.testing.expectEqual(.rust, reg.lookupSourceFile("test.ll").?);
}

// ── Test 7: getDefault() fallback behavior ──

test "getDefault: null when not set" {
    const alloc = std.testing.allocator;
    var reg = try LanguageOverrideRegistry.init(alloc);
    defer reg.deinit();

    // Fresh registry has no default
    try std.testing.expect(reg.getDefault() == null);

    // Having other rules doesn't set a default
    try reg.addExact("x", .rust);
    try std.testing.expect(reg.getDefault() == null);
}

test "getDefault: returns set value" {
    const alloc = std.testing.allocator;
    var reg = try LanguageOverrideRegistry.init(alloc);
    defer reg.deinit();

    reg.setDefault(.c);
    try std.testing.expectEqual(.c, reg.getDefault().?);

    // Can change
    reg.setDefault(.zig);
    try std.testing.expectEqual(.zig, reg.getDefault().?);

    // Can change again
    reg.setDefault(null);
    try std.testing.expect(reg.getDefault() == null);
}

// ── Test 8: Edge cases ──

test "edge case: empty string lookups" {
    const alloc = std.testing.allocator;
    var reg = try LanguageOverrideRegistry.init(alloc);
    defer reg.deinit();

    // Empty string should not crash or match anything
    try std.testing.expect(reg.lookup("") == null);
    try std.testing.expect(reg.lookupSourceFile("") == null);
}

test "edge case: duplicate keys in exact map" {
    const alloc = std.testing.allocator;
    var reg = try LanguageOverrideRegistry.init(alloc);
    defer reg.deinit();

    // Adding same key twice — second overwrites
    try reg.addExact("dup_key", .c);
    try reg.addExact("dup_key", .rust);
    // Last write wins (HashMap semantics)
    try std.testing.expectEqual(.rust, reg.lookup("dup_key").?);
}

test "edge case: special characters in keys" {
    const alloc = std.testing.allocator;
    var reg = try LanguageOverrideRegistry.init(alloc);
    defer reg.deinit();

    // Keys with underscores, colons, dots, etc.
    try reg.addExact("_ZN5alloc5boxed19Box$LT$T$GT$4leak17h", .rust);
    try reg.addExact("Java_com_example_Foo", .java);
    try reg.addExact("PyInit_mymodule", .python);
    try reg.addPrefix("ngx_", .c);
    try reg.addSuffix(".vtable", .cpp);

    try std.testing.expectEqual(.rust, reg.lookup("_ZN5alloc5boxed19Box$LT$T$GT$4leak17h").?);
    try std.testing.expectEqual(.java, reg.lookup("Java_com_example_Foo").?);
    try std.testing.expectEqual(.python, reg.lookup("PyInit_mymodule").?);
    try std.testing.expectEqual(.c, reg.lookup("ngx_http_handler").?);
    try std.testing.expectEqual(.cpp, reg.lookup("MyClass.vtable").?);
}

test "edge case: isEmpty reflects all fields" {
    const alloc = std.testing.allocator;

    // Fresh is empty
    var r1 = try LanguageOverrideRegistry.init(alloc);
    defer r1.deinit();
    try std.testing.expect(r1.isEmpty());

    // Each field makes it non-empty independently
    var r2 = try LanguageOverrideRegistry.init(alloc);
    defer r2.deinit();
    try r2.addExact("x", .rust);
    try std.testing.expect(!r2.isEmpty());

    var r3 = try LanguageOverrideRegistry.init(alloc);
    defer r3.deinit();
    try r3.addPrefix("p", .c);
    try std.testing.expect(!r3.isEmpty());

    var r4 = try LanguageOverrideRegistry.init(alloc);
    defer r4.deinit();
    try r4.addSuffix("s", .rust);
    try std.testing.expect(!r4.isEmpty());

    var r5 = try LanguageOverrideRegistry.init(alloc);
    defer r5.deinit();
    try r5.addSourceFile("f.ll", .c);
    try std.testing.expect(!r5.isEmpty());

    var r6 = try LanguageOverrideRegistry.init(alloc);
    defer r6.deinit();
    r6.setDefault(.zig);
    try std.testing.expect(!r6.isEmpty());
}

test "edge case: very long prefix vs shorter prefix on same string" {
    const alloc = std.testing.allocator;
    var reg = try LanguageOverrideRegistry.init(alloc);
    defer reg.deinit();

    try reg.addPrefix("a", .c);
    try reg.addPrefix("ab", .cpp);
    try reg.addPrefix("abc", .rust);
    try reg.addPrefix("abcd", .zig);
    reg.sortPrefixRules();

    // Longest prefix "abcd" should win
    try std.testing.expectEqual(.zig, reg.lookup("abcdefgh").?);

    // "abc" should match for strings starting with "abc" but not "abcd"
    try std.testing.expectEqual(.rust, reg.lookup("abcXYZ").?);

    // "ab" for strings starting with "ab" but not "abc"
    try std.testing.expectEqual(.cpp, reg.lookup("ab123").?);

    // Just "a"
    try std.testing.expectEqual(.c, reg.lookup("a_only").?);
}

test "edge case: loadFromJson with all sections empty" {
    const alloc = std.testing.allocator;
    var reg = try LanguageOverrideRegistry.init(alloc);
    defer reg.deinit();

    try reg.loadFromJson(
        \\{
        \\  "exact": {},
        \\  "prefix": {},
        \\  "suffix": {},
        \\  "source_files": {}
        \\}
        \\
    );
    // Should be empty but not crash
    try std.testing.expect(reg.isEmpty());

    // All lookups return null
    try std.testing.expect(reg.lookup("anything") == null);
    try std.testing.expect(reg.lookupSourceFile("anything") == null);
    try std.testing.expect(reg.getDefault() == null);
}

test "edge case: mergeFromCLI with all-null slices" {
    const alloc = std.testing.allocator;
    var reg = try LanguageOverrideRegistry.init(alloc);
    defer reg.deinit();

    // Pre-populate some data
    try reg.addExact("keep_me", .c);
    reg.setDefault(.zig);

    // Merge empty CLI — should preserve existing data
    const cli = LanguageOverrideRegistry.CLIOverrides{
        .exact = &.{},
        .prefix = &.{},
        .suffix = &.{},
        .source_files = &.{},
        .default_lang = null,
    };
    try reg.mergeFromCLI(cli);

    try std.testing.expectEqual(.c, reg.lookup("keep_me").?);
    try std.testing.expectEqual(.zig, reg.getDefault().?);
}
