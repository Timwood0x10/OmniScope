//! Language Override Registry — per-symbol and per-file language overrides
//!
//! Provides a registry for overriding auto-detected languages on a per-symbol,
//! per-prefix, per-suffix, or per-source-file basis.
//!
//! ## Priority Chain (lookup)
//!   1. Exact match (func_name → Language)  — O(1) HashMap
//!   2. Prefix match (longest prefix wins)  — sorted by length descending
//!   3. Suffix match (longest suffix wins)  — sorted by length descending
//!   4. null → caller should fall back to auto-detection
//!
//! ## Usage
//! ```zig
//! var registry = try LanguageOverrideRegistry.init(allocator);
//! defer registry.deinit();
//!
//! // Add rules
//! try registry.addExact("__rust_alloc", .rust);
//! try registry.addPrefix("sqlite3_", .c);
//! try registry.addSuffix("_rs", .rust);
//! registry.setDefault(.c);
//!
//! // Sort prefix/suffix rules after all additions
//! registry.sortPrefixRules();
//! registry.sortSuffixRules();
//!
//! // Lookup
//! const lang = registry.lookup("__rust_alloc") orelse autoDetect(name);
//! ```

const std = @import("std");

/// Re-export the canonical Language enum from diag/issue.zig.
/// This is the single source of truth for Language across the FFI analysis pipeline.
pub const Language = @import("../diag/issue.zig").FFIBoundary.Language;

pub const LanguageOverrideRegistry = struct {
    allocator: std.mem.Allocator,

    /// (a) Exact match: func_name → Language (O(1) lookup)
    exact_map: std.StringHashMap(Language),

    /// (b) Prefix match: sorted by prefix length descending (longest wins)
    prefix_rules: std.ArrayList(PrefixRule),

    /// (c) Suffix match: sorted by suffix length descending (longest wins)
    suffix_rules: std.ArrayList(SuffixRule),

    /// (d) Source file level: filename → Language
    source_file_map: std.StringHashMap(Language),

    /// (e) Global default language (may be null)
    default_lang: ?Language = null,

    pub const PrefixRule = struct {
        prefix: []const u8,
        lang: Language,
    };

    pub const SuffixRule = struct {
        suffix: []const u8,
        lang: Language,
    };

    /// Release all owned memory.
    pub fn deinit(self: *LanguageOverrideRegistry) void {
        const alloc = self.allocator;

        // Free owned strings in prefix_rules, then deinit the list
        for (self.prefix_rules.items) |*rule| {
            alloc.free(rule.prefix);
        }
        self.prefix_rules.deinit(alloc);

        // Free owned strings in suffix_rules, then deinit the list
        for (self.suffix_rules.items) |*rule| {
            alloc.free(rule.suffix);
        }
        self.suffix_rules.deinit(alloc);

        // StringHashMap keys are owned by the HashMap
        var exact_iter = self.exact_map.iterator();
        while (exact_iter.next()) |entry| {
            alloc.free(entry.key_ptr.*);
        }
        self.exact_map.deinit();

        var sf_iter = self.source_file_map.iterator();
        while (sf_iter.next()) |entry| {
            alloc.free(entry.key_ptr.*);
        }
        self.source_file_map.deinit();
    }

    /// Initialize a new empty registry.
    pub fn init(allocator: std.mem.Allocator) !LanguageOverrideRegistry {
        return .{
            .allocator = allocator,
            .exact_map = std.StringHashMap(Language).init(allocator),
            .prefix_rules = @as(std.ArrayList(PrefixRule), .empty),
            .suffix_rules = @as(std.ArrayList(SuffixRule), .empty),
            .source_file_map = std.StringHashMap(Language).init(allocator),
            .default_lang = null,
        };
    }

    /// Add an exact match rule. Owns the string copy.
    pub fn addExact(self: *LanguageOverrideRegistry, name: []const u8, lang: Language) !void {
        const owned = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(owned);
        try self.exact_map.put(owned, lang);
    }

    /// Add a prefix rule. After adding all prefixes, call sortPrefixRules().
    pub fn addPrefix(self: *LanguageOverrideRegistry, prefix: []const u8, lang: Language) !void {
        const owned = try self.allocator.dupe(u8, prefix);
        errdefer self.allocator.free(owned);
        try self.prefix_rules.append(self.allocator, .{ .prefix = owned, .lang = lang });
    }

    /// Add a suffix rule. After adding all suffixes, call sortSuffixRules().
    pub fn addSuffix(self: *LanguageOverrideRegistry, suffix: []const u8, lang: Language) !void {
        const owned = try self.allocator.dupe(u8, suffix);
        errdefer self.allocator.free(owned);
        try self.suffix_rules.append(self.allocator, .{ .suffix = owned, .lang = lang });
    }

    /// Sort prefix rules by length descending (longest match wins).
    pub fn sortPrefixRules(self: *LanguageOverrideRegistry) void {
        std.sort.insertion(PrefixRule, self.prefix_rules.items, {}, struct {
            fn lessThan(_: void, a: PrefixRule, b: PrefixRule) bool {
                return a.prefix.len > b.prefix.len;
            }
        }.lessThan);
    }

    /// Sort suffix rules by length descending.
    pub fn sortSuffixRules(self: *LanguageOverrideRegistry) void {
        std.sort.insertion(SuffixRule, self.suffix_rules.items, {}, struct {
            fn lessThan(_: void, a: SuffixRule, b: SuffixRule) bool {
                return a.suffix.len > b.suffix.len;
            }
        }.lessThan);
    }

    /// Set the global default language.
    pub fn setDefault(self: *LanguageOverrideRegistry, lang: Language) void {
        self.default_lang = lang;
    }

    /// Add a source file language mapping.
    pub fn addSourceFile(self: *LanguageOverrideRegistry, filename: []const u8, lang: Language) !void {
        // Free old key if overwriting an existing entry (prevents memory leak)
        if (self.source_file_map.fetchRemove(filename)) |removed| {
            self.allocator.free(removed.key);
        }
        const owned = try self.allocator.dupe(u8, filename);
        errdefer self.allocator.free(owned);
        try self.source_file_map.put(owned, lang);
    }

    /// Lookup function: find language for a symbol name.
    ///
    /// Priority: exact > prefix(longest) > suffix(longest) > null(not found)
    /// Caller should fallback to auto-detection if null is returned.
    pub fn lookup(self: *const LanguageOverrideRegistry, func_name: []const u8) ?Language {
        // (1) Exact match — O(1)
        if (self.exact_map.get(func_name)) |lang| {
            return lang;
        }

        // (2) Prefix match — longest first
        for (self.prefix_rules.items) |rule| {
            if (std.mem.startsWith(u8, func_name, rule.prefix)) {
                return rule.lang;
            }
        }

        // (3) Suffix match — longest first
        for (self.suffix_rules.items) |rule| {
            if (std.mem.endsWith(u8, func_name, rule.suffix)) {
                return rule.lang;
            }
        }

        return null; // Not found — caller should use auto-detection
    }

    // TODO: Wire lookupSourceFile() into language_detector or PassContext.lookupFunctionLanguage().
    // Currently source_file_map is populated from --source-lang but no pass calls this method.
    // See bugs.md item #5 for details.
    /// Lookup source file language. Tries basename first, then full path.
    pub fn lookupSourceFile(self: *const LanguageOverrideRegistry, filename: []const u8) ?Language {
        const basename = std.fs.path.basename(filename);
        return self.source_file_map.get(basename) orelse self.source_file_map.get(filename);
    }

    /// Get the default language (may be null).
    pub fn getDefault(self: *const LanguageOverrideRegistry) ?Language {
        return self.default_lang;
    }

    /// Check if the registry has any rules configured.
    pub fn isEmpty(self: *const LanguageOverrideRegistry) bool {
        return self.exact_map.count() == 0 and
            self.prefix_rules.items.len == 0 and
            self.suffix_rules.items.len == 0 and
            self.source_file_map.count() == 0 and
            self.default_lang == null;
    }

    // ── JSON Loading ──

    /// Parse a language string ("rust", "c", "cpp", etc.) into Language enum.
    pub fn parseLangString(s: []const u8) ?Language {
        if (std.mem.eql(u8, s, "c")) return .c;
        if (std.mem.eql(u8, s, "cpp") or std.mem.eql(u8, s, "c++")) return .cpp;
        if (std.mem.eql(u8, s, "rust")) return .rust;
        if (std.mem.eql(u8, s, "zig")) return .zig;
        if (std.mem.eql(u8, s, "go")) return .go;
        if (std.mem.eql(u8, s, "python") or std.mem.eql(u8, s, "py")) return .python;
        if (std.mem.eql(u8, s, "java")) return .java;
        if (std.mem.eql(u8, s, "csharp") or std.mem.eql(u8, s, "c#")) return .csharp;
        if (std.mem.eql(u8, s, "unknown")) return .unknown;
        return null;
    }

    /// Load overrides from JSON value (the "overrides" object from config).
    ///
    /// Expected JSON structure:
    /// ```json
    /// {
    ///   "exact": { "__rust_alloc": "rust", ... },
    ///   "prefix": { "sqlite3_": "c", ... },
    ///   "suffix": { "_rs": "rust", ... },
    ///   "source_files": { "file.ll": "c", ... },
    ///   "default_language": "c"
    /// }
    /// ```
    ///
    /// Note: Uses std.json.parseFromSlice with Value type for dynamic JSON parsing.
    pub fn loadFromJson(self: *LanguageOverrideRegistry, json_str: []const u8) !void {
        const parsed = std.json.parseFromSlice(std.json.Value, self.allocator, json_str, .{}) catch return;
        defer parsed.deinit();

        const root = parsed.value;

        if (root != .object) return;

        // Parse exact matches
        if (root.object.get("exact")) |exact_obj| {
            if (exact_obj == .object) {
                var iter = exact_obj.object.iterator();
                while (iter.next()) |entry| {
                    if (entry.value_ptr.* == .string) {
                        const lang = parseLangString((entry.value_ptr.*).string) orelse continue;
                        try self.addExact(entry.key_ptr.*, lang);
                    }
                }
            }
        }

        // Parse prefix rules
        if (root.object.get("prefix")) |prefix_obj| {
            if (prefix_obj == .object) {
                var iter = prefix_obj.object.iterator();
                while (iter.next()) |entry| {
                    if (entry.value_ptr.* == .string) {
                        const lang = parseLangString((entry.value_ptr.*).string) orelse continue;
                        try self.addPrefix(entry.key_ptr.*, lang);
                    }
                }
                self.sortPrefixRules();
            }
        }

        // Parse suffix rules
        if (root.object.get("suffix")) |suffix_obj| {
            if (suffix_obj == .object) {
                var iter = suffix_obj.object.iterator();
                while (iter.next()) |entry| {
                    if (entry.value_ptr.* == .string) {
                        const lang = parseLangString((entry.value_ptr.*).string) orelse continue;
                        try self.addSuffix(entry.key_ptr.*, lang);
                    }
                }
                self.sortSuffixRules();
            }
        }

        // Parse source file mappings
        if (root.object.get("source_files")) |sf_obj| {
            if (sf_obj == .object) {
                var iter = sf_obj.object.iterator();
                while (iter.next()) |entry| {
                    if (entry.value_ptr.* == .string) {
                        const lang = parseLangString((entry.value_ptr.*).string) orelse continue;
                        try self.addSourceFile(entry.key_ptr.*, lang);
                    }
                }
            }
        }

        // Parse default language
        if (root.object.get("default_language")) |dl| {
            if (dl == .string) {
                if (parseLangString(dl.string)) |lang| {
                    self.setDefault(lang);
                }
            }
        }
    }

    /// Load from CLI-style key=value pairs.
    /// Called after all CLI args are parsed.
    /// CLI overrides take priority over JSON config.
    pub fn mergeFromCLI(self: *LanguageOverrideRegistry, cli_overrides: CLIOverrides) !void {
        // CLI exact overrides — overwrite/add to existing
        for (cli_overrides.exact) |entry| {
            const lang = parseLangString(entry[1]) orelse continue;
            // Remove existing exact entry if present, then add (CLI wins)
            if (self.exact_map.fetchRemove(entry[0])) |removed| {
                self.allocator.free(removed.key);
            }
            try self.addExact(entry[0], lang);
        }

        // CLI prefix overrides — append and re-sort
        for (cli_overrides.prefix) |entry| {
            const lang = parseLangString(entry[1]) orelse continue;
            try self.addPrefix(entry[0], lang);
        }
        if (cli_overrides.prefix.len > 0) self.sortPrefixRules();

        // CLI suffix overrides
        for (cli_overrides.suffix) |entry| {
            const lang = parseLangString(entry[1]) orelse continue;
            try self.addSuffix(entry[0], lang);
        }
        if (cli_overrides.suffix.len > 0) self.sortSuffixRules();

        // Source file mappings
        for (cli_overrides.source_files) |entry| {
            const lang = parseLangString(entry[1]) orelse continue;
            try self.addSourceFile(entry[0], lang);
        }

        // Default language (CLI always wins)
        if (cli_overrides.default_lang) |dl| {
            if (parseLangString(dl)) |lang| {
                self.setDefault(lang);
            }
        }
    }

    /// CLI override data passed from argument parsing.
    pub const CLIOverrides = struct {
        exact: []const KVPair,
        prefix: []const KVPair,
        suffix: []const KVPair,
        source_files: []const KVPair,
        default_lang: ?[]const u8,

        pub const KVPair = struct { []const u8, []const u8 };
    };
};

// ── Tests ──

test "LanguageOverrideRegistry - exact match" {
    const alloc = std.testing.allocator;
    var reg = try LanguageOverrideRegistry.init(alloc);
    defer reg.deinit();

    try reg.addExact("__rust_alloc", .rust);
    try reg.addExact("malloc", .c);
    try reg.addExact("Py_INCREF", .python);

    try std.testing.expectEqual(.rust, reg.lookup("__rust_alloc").?);
    try std.testing.expectEqual(.c, reg.lookup("malloc").?);
    try std.testing.expectEqual(.python, reg.lookup("Py_INCREF").?);

    // Non-existent returns null
    try std.testing.expect(reg.lookup("unknown_func") == null);
}

test "LanguageOverrideRegistry - prefix match longest wins" {
    const alloc = std.testing.allocator;
    var reg = try LanguageOverrideRegistry.init(alloc);
    defer reg.deinit();

    // Add shorter prefix first (will be sorted correctly)
    try reg.addPrefix("sql_", .c);
    try reg.addPrefix("sqlite3_", .c);
    try reg.addPrefix("sqlite3_open_", .c);
    reg.sortPrefixRules();

    // Longest prefix should win
    try std.testing.expectEqual(.c, reg.lookup("sqlite3_open_db").?);
    try std.testing.expectEqual(.c, reg.lookup("sqlite3_exec").?);
    try std.testing.expectEqual(.c, reg.lookup("sql_database").?);

    // No prefix match
    try std.testing.expect(reg.lookup("malloc") == null);
}

test "LanguageOverrideRegistry - suffix match" {
    const alloc = std.testing.allocator;
    var reg = try LanguageOverrideRegistry.init(alloc);
    defer reg.deinit();

    try reg.addSuffix("_rs", .rust);
    try reg.addSuffix("_vtable", .c);
    reg.sortSuffixRules();

    try std.testing.expectEqual(.rust, reg.lookup("my_function_rs").?);
    try std.testing.expectEqual(.c, reg.lookup("my_class_vtable").?);

    // No suffix match
    try std.testing.expect(reg.lookup("plain_func") == null);
}

test "LanguageOverrideRegistry - priority chain exact > prefix > suffix" {
    const alloc = std.testing.allocator;
    var reg = try LanguageOverrideRegistry.init(alloc);
    defer reg.deinit();

    // Set up conflicting rules: same name matches exact, prefix, AND suffix
    try reg.addExact("special_func", .java);
    try reg.addPrefix("special_", .go);
    try reg.addSuffix("_func", .rust);
    reg.sortPrefixRules();
    reg.sortSuffixRules();

    // Exact should always win
    try std.testing.expectEqual(.java, reg.lookup("special_func").?);

    // A name that matches prefix but NOT exact should get prefix
    try std.testing.expectEqual(.go, reg.lookup("special_other").?);

    // A name that matches only suffix
    try std.testing.expectEqual(.rust, reg.lookup("other_func").?);
}

test "LanguageOverrideRegistry - no match returns null" {
    const alloc = std.testing.allocator;
    var reg = try LanguageOverrideRegistry.init(alloc);
    defer reg.deinit();

    try std.testing.expect(reg.lookup("") == null);
    try std.testing.expect(reg.lookup("anything") == null);
    try std.testing.expect(reg.lookup("_") == null);
}

test "LanguageOverrideRegistry - default language" {
    const alloc = std.testing.allocator;
    var reg = try LanguageOverrideRegistry.init(alloc);
    defer reg.deinit();

    // No default set initially
    try std.testing.expect(reg.getDefault() == null);

    reg.setDefault(.c);
    try std.testing.expectEqual(.c, reg.getDefault().?);

    // Can change default
    reg.setDefault(.rust);
    try std.testing.expectEqual(.rust, reg.getDefault().?);
}

test "LanguageOverrideRegistry - isEmpty" {
    const alloc = std.testing.allocator;
    var reg = try LanguageOverrideRegistry.init(alloc);
    defer reg.deinit();

    // Freshly created is empty
    try std.testing.expect(reg.isEmpty());

    // Adding any rule makes it non-empty
    try reg.addExact("x", .rust);
    try std.testing.expect(!reg.isEmpty());

    // Check each field independently
    var reg2 = try LanguageOverrideRegistry.init(alloc);
    defer reg2.deinit();
    try reg2.addPrefix("p", .c);
    try std.testing.expect(!reg2.isEmpty());

    var reg3 = try LanguageOverrideRegistry.init(alloc);
    defer reg3.deinit();
    try reg3.addSuffix("s", .rust);
    try std.testing.expect(!reg3.isEmpty());

    var reg4 = try LanguageOverrideRegistry.init(alloc);
    defer reg4.deinit();
    try reg4.addSourceFile("f.ll", .c);
    try std.testing.expect(!reg4.isEmpty());

    var reg5 = try LanguageOverrideRegistry.init(alloc);
    defer reg5.deinit();
    reg5.setDefault(.zig);
    try std.testing.expect(!reg5.isEmpty());
}

test "LanguageOverrideRegistry - source file lookup" {
    const alloc = std.testing.allocator;
    var reg = try LanguageOverrideRegistry.init(alloc);
    defer reg.deinit();

    try reg.addSourceFile("generated.ll", .c);
    try reg.addSourceFile("/path/to/deep/file.ll", .cpp);

    // Basename match
    try std.testing.expectEqual(.c, reg.lookupSourceFile("generated.ll").?);
    try std.testing.expectEqual(.c, reg.lookupSourceFile("./generated.ll").?);
    try std.testing.expectEqual(.c, reg.lookupSourceFile("/any/path/generated.ll").?);

    // Full path match
    try std.testing.expectEqual(.cpp, reg.lookupSourceFile("/path/to/deep/file.ll").?);

    // No match
    try std.testing.expect(reg.lookupSourceFile("unknown.ll") == null);
}

test "LanguageOverrideRegistry - CLI merge overwrites exact" {
    const alloc = std.testing.allocator;
    var reg = try LanguageOverrideRegistry.init(alloc);
    defer reg.deinit();

    // Pre-populate from JSON-like source
    try reg.addExact("malloc", .c);
    try reg.addPrefix("py_", .python);
    reg.sortPrefixRules();

    // CLI overrides
    const cli = LanguageOverrideRegistry.CLIOverrides{
        .exact = &.{.{ "malloc", "rust" }}, // Overwrite!
        .prefix = &.{.{ "go_", "go" }},
        .suffix = &.{},
        .source_files = &.{},
        .default_lang = "zig",
    };
    try reg.mergeFromCLI(cli);

    // CLI exact should have overwritten
    try std.testing.expectEqual(.rust, reg.lookup("malloc").?);

    // Original prefix still works
    try std.testing.expectEqual(.python, reg.lookup("py_something").?);

    // New prefix added
    try std.testing.expectEqual(.go, reg.lookup("go_runtime").?);

    // Default language set from CLI
    try std.testing.expectEqual(.zig, reg.getDefault().?);
}

test "LanguageOverrideRegistry - parseLangString valid values" {
    try std.testing.expectEqual(.c, LanguageOverrideRegistry.parseLangString("c").?);
    try std.testing.expectEqual(.cpp, LanguageOverrideRegistry.parseLangString("cpp").?);
    try std.testing.expectEqual(.cpp, LanguageOverrideRegistry.parseLangString("c++").?);
    try std.testing.expectEqual(.rust, LanguageOverrideRegistry.parseLangString("rust").?);
    try std.testing.expectEqual(.zig, LanguageOverrideRegistry.parseLangString("zig").?);
    try std.testing.expectEqual(.go, LanguageOverrideRegistry.parseLangString("go").?);
    try std.testing.expectEqual(.python, LanguageOverrideRegistry.parseLangString("python").?);
    try std.testing.expectEqual(.python, LanguageOverrideRegistry.parseLangString("py").?);
    try std.testing.expectEqual(.java, LanguageOverrideRegistry.parseLangString("java").?);
    try std.testing.expectEqual(.csharp, LanguageOverrideRegistry.parseLangString("csharp").?);
    try std.testing.expectEqual(.csharp, LanguageOverrideRegistry.parseLangString("c#").?);
    try std.testing.expectEqual(.unknown, LanguageOverrideRegistry.parseLangString("unknown").?);
}

test "LanguageOverrideRegistry - parseLangString invalid values" {
    try std.testing.expect(LanguageOverrideRegistry.parseLangString("") == null);
    try std.testing.expect(LanguageOverrideRegistry.parseLangString("invalid") == null);
    try std.testing.expect(LanguageOverrideRegistry.parseLangString("C") == null); // case-sensitive
    try std.testing.expect(LanguageOverrideRegistry.parseLangString("Rust") == null);
}

test "LanguageOverrideRegistry - loadFromJson basic" {
    const alloc = std.testing.allocator;
    var reg = try LanguageOverrideRegistry.init(alloc);
    defer reg.deinit();

    const json =
        \\{
        \\  "exact": {"__rust_alloc": "rust", "malloc": "c"},
        \\  "prefix": {"sqlite3_": "c"},
        \\  "suffix": {"_rs": "rust"},
        \\  "default_language": "zig"
        \\}
    ;
    try reg.loadFromJson(json);

    try std.testing.expectEqual(.rust, reg.lookup("__rust_alloc").?);
    try std.testing.expectEqual(.c, reg.lookup("malloc").?);
    try std.testing.expectEqual(.c, reg.lookup("sqlite3_open").?);
    try std.testing.expectEqual(.rust, reg.lookup("something_rs").?);
    try std.testing.expectEqual(.zig, reg.getDefault().?);
}

test "LanguageOverrideRegistry - loadFromJson source_files" {
    const alloc = std.testing.allocator;
    var reg = try LanguageOverrideRegistry.init(alloc);
    defer reg.deinit();

    const json =
        \\{
        \\  "source_files": {"generated.ll": "c", "wrapper.go": "go"}
        \\}
    ;
    try reg.loadFromJson(json);

    try std.testing.expectEqual(.c, reg.lookupSourceFile("generated.ll").?);
    try std.testing.expectEqual(.go, reg.lookupSourceFile("wrapper.go").?);
}
