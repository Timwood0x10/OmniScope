//! Rust Semantic Patterns
//!
//! This module registers semantic patterns specific to Rust language.
//! These patterns help identify common Rust constructs and resolve
//! their safety properties in the semantic resolution tree.

const std = @import("std");
const semantic_patterns = @import("../../semantics/semantic_patterns.zig");
const PatternRegistry = semantic_patterns.PatternRegistry;
const PatternUtils = semantic_patterns.PatternUtils;
const SemanticKind = @import("../../semantics/semantic_tree.zig").SemanticKind;
const Resolution = @import("../../semantics/semantic_tree.zig").Resolution;
const LanguageHint = @import("../../semantics/semantic_tree.zig").LanguageHint;

/// Register all Rust semantic patterns
pub fn registerRustPatterns(registry: *PatternRegistry) !void {
    // Drop patterns - these are compiler-generated and safe
    try registry.registerPattern(.{
        .name = "rust_drop_in_place",
        .matcher = PatternUtils.substringMatcher("drop_in_place"),
        .resolver = PatternUtils.simpleResolver(SemanticKind.release, Resolution.released, 95),
        .language = .rust,
        .priority = 100,
    });

    try registry.registerPattern(.{
        .name = "rust_drop_glue",
        .matcher = PatternUtils.substringMatcher("drop_glue"),
        .resolver = PatternUtils.simpleResolver(SemanticKind.release, Resolution.released, 95),
        .language = .rust,
        .priority = 99,
    });

    try registry.registerPattern(.{
        .name = "rust_real_drop_in_place",
        .matcher = PatternUtils.substringMatcher("real_drop_in_place"),
        .resolver = PatternUtils.simpleResolver(SemanticKind.release, Resolution.released, 95),
        .language = .rust,
        .priority = 98,
    });

    // Deallocation patterns - part of drop chain
    try registry.registerPattern(.{
        .name = "rust_dealloc",
        .matcher = PatternUtils.substringMatcher("__rust_dealloc"),
        .resolver = PatternUtils.simpleResolver(SemanticKind.release, Resolution.released, 90),
        .language = .rust,
        .priority = 97,
    });

    try registry.registerPattern(.{
        .name = "rust_rdl_dealloc",
        .matcher = PatternUtils.substringMatcher("__rdl_dealloc"),
        .resolver = PatternUtils.simpleResolver(SemanticKind.release, Resolution.released, 90),
        .language = .rust,
        .priority = 96,
    });

    try registry.registerPattern(.{
        .name = "rust_rg_dealloc",
        .matcher = PatternUtils.substringMatcher("__rg_dealloc"),
        .resolver = PatternUtils.simpleResolver(SemanticKind.release, Resolution.released, 90),
        .language = .rust,
        .priority = 95,
    });

    // Safe provenance patterns
    try registry.registerPattern(.{
        .name = "rust_nonnull",
        .matcher = PatternUtils.substringMatcher("NonNull"),
        .resolver = PatternUtils.simpleResolver(SemanticKind.provenance, Resolution.safe, 85),
        .language = .rust,
        .priority = 94,
    });

    try registry.registerPattern(.{
        .name = "rust_slice_from_raw",
        .matcher = PatternUtils.substringMatcher("slice_from_raw"),
        .resolver = PatternUtils.simpleResolver(SemanticKind.provenance, Resolution.safe, 85),
        .language = .rust,
        .priority = 93,
    });

    // Ownership transfer patterns
    try registry.registerPattern(.{
        .name = "rust_into_raw",
        .matcher = PatternUtils.substringMatcher("into_raw"),
        .resolver = PatternUtils.simpleResolver(SemanticKind.ownership_transfer, Resolution.safe, 80),
        .language = .rust,
        .priority = 92,
    });

    try registry.registerPattern(.{
        .name = "rust_from_raw",
        .matcher = PatternUtils.substringMatcher("from_raw"),
        .resolver = PatternUtils.simpleResolver(SemanticKind.ownership_transfer, Resolution.safe, 80),
        .language = .rust,
        .priority = 91,
    });

    // Box patterns
    try registry.registerPattern(.{
        .name = "rust_box_new",
        .matcher = PatternUtils.substringMatcher("Box::new"),
        .resolver = PatternUtils.simpleResolver(SemanticKind.allocation, Resolution.unresolved, 70),
        .language = .rust,
        .priority = 90,
    });

    try registry.registerPattern(.{
        .name = "rust_box_drop",
        .matcher = PatternUtils.substringMatcher("Box::drop"),
        .resolver = PatternUtils.simpleResolver(SemanticKind.release, Resolution.released, 90),
        .language = .rust,
        .priority = 89,
    });

    // Vec patterns
    try registry.registerPattern(.{
        .name = "rust_vec_new",
        .matcher = PatternUtils.substringMatcher("Vec::new"),
        .resolver = PatternUtils.simpleResolver(SemanticKind.allocation, Resolution.unresolved, 70),
        .language = .rust,
        .priority = 88,
    });

    try registry.registerPattern(.{
        .name = "rust_vec_drop",
        .matcher = PatternUtils.substringMatcher("Vec::drop"),
        .resolver = PatternUtils.simpleResolver(SemanticKind.release, Resolution.released, 90),
        .language = .rust,
        .priority = 87,
    });

    // String patterns
    try registry.registerPattern(.{
        .name = "rust_string_new",
        .matcher = PatternUtils.substringMatcher("String::new"),
        .resolver = PatternUtils.simpleResolver(SemanticKind.allocation, Resolution.unresolved, 70),
        .language = .rust,
        .priority = 86,
    });

    try registry.registerPattern(.{
        .name = "rust_string_drop",
        .matcher = PatternUtils.substringMatcher("String::drop"),
        .resolver = PatternUtils.simpleResolver(SemanticKind.release, Resolution.released, 90),
        .language = .rust,
        .priority = 85,
    });

    // Runtime wrapper patterns
    try registry.registerPattern(.{
        .name = "rust_panic",
        .matcher = PatternUtils.substringMatcher("panic"),
        .resolver = PatternUtils.simpleResolver(SemanticKind.runtime_wrapper, Resolution.unresolved, 60),
        .language = .rust,
        .priority = 50,
    });

    try registry.registerPattern(.{
        .name = "rust_unwind",
        .matcher = PatternUtils.substringMatcher("unwind"),
        .resolver = PatternUtils.simpleResolver(SemanticKind.runtime_wrapper, Resolution.unresolved, 60),
        .language = .rust,
        .priority = 49,
    });
}

/// Test function for Rust patterns
pub fn testRustPatterns() void {
    const allocator = std.heap.page_allocator;
    var registry = PatternRegistry.init(allocator);
    defer registry.deinit();

    registerRustPatterns(&registry) catch return;

    // Test drop patterns
    const drop_result = registry.resolveFunction("drop_in_place");
    std.debug.assert(drop_result != null);
    std.debug.assert(drop_result.?.resolution == Resolution.released);

    // Test dealloc patterns
    const dealloc_result = registry.resolveFunction("__rust_dealloc");
    std.debug.assert(dealloc_result != null);
    std.debug.assert(dealloc_result.?.resolution == Resolution.released);

    // Test provenance patterns
    const nonnull_result = registry.resolveFunction("NonNull::new");
    std.debug.assert(nonnull_result != null);
    std.debug.assert(nonnull_result.?.resolution == Resolution.safe);

    // Test ownership transfer patterns
    const into_raw_result = registry.resolveFunction("into_raw");
    std.debug.assert(into_raw_result != null);
    std.debug.assert(into_raw_result.?.resolution == Resolution.safe);
}
