//! Surface Classifier — Layer 2: Debug Origin / Source Path Provenance
//!
//! Classifies function origin from DISubprogram → DIFile source path.
//! This replaces name-based whitelisting with provenance matching.
//!
//! Key insight: Rust stdlib always lives at /rustc/<hash>/library/ regardless
//! of version or project. C++ STL is at /include/c++/. No crate names needed.

const std = @import("std");
const c = @import("../../ir/llvm_raw.zig").c;
const log = @import("../../common/log.zig");
const SurfaceHint = @import("surface_classifier.zig").SurfaceHint;
const FunctionSurface = @import("surface_classifier.zig").FunctionSurface;

/// Source provenance determined from DIFile path.
pub const SourceProvenance = enum {
    user_code,
    stdlib,
    dependency,
    build_generated,
    unknown,
};

/// Classify function surface from DISubprogram → DIFile source path.
///
/// Returns null if debug info is not available or provenance is unknown,
/// in which case the decision defers to other layers.
pub fn classifyDebugOrigin(func: c.LLVMValueRef) ?SurfaceHint {
    const sp = c.LLVMGetSubprogram(func);
    if (@intFromPtr(sp) == 0) return null;

    const file_ref = c.LLVMDIScopeGetFile(sp);
    if (@intFromPtr(file_ref) == 0) return null;

    var dir_len: c_uint = 0;
    const dir_ptr = c.LLVMDIFileGetDirectory(file_ref, &dir_len);
    const max_path_len: c_uint = 8192;
    if (@intFromPtr(dir_ptr) == 0 or dir_len == 0 or dir_len > max_path_len) return null;
    const dir = dir_ptr[0..dir_len];

    var name_len: c_uint = 0;
    const name_ptr = c.LLVMDIFileGetFilename(file_ref, &name_len);
    if (@intFromPtr(name_ptr) == 0 or name_len == 0 or name_len > max_path_len) return null;
    const filename = name_ptr[0..name_len];

    const provenance = classifySourcePath(dir, filename);

    // Diagnostic: log source path when provenance is unknown — this is the
    // key failure mode where L2 has debug info but path doesn't match any rule.
    if (provenance == .unknown) {
        log.debug("[L2-UNKNOWN] dir='{s}' file='{s}' — no provenance rule matched", .{ dir, filename });
    }

    return switch (provenance) {
        .user_code => .{
            .surface = .user_code,
            .confidence = .high,
            .reason = "source path in workspace",
        },
        .stdlib => .{
            .surface = .standard_library,
            .confidence = .high,
            .reason = "source path in standard library",
        },
        .dependency => .{
            .surface = .dependency,
            .confidence = .high,
            .reason = "source path in dependency registry",
        },
        .build_generated => .{
            .surface = .compiler_generated,
            .confidence = .medium,
            .reason = "source path in build output",
        },
        .unknown => null,
    };
}

/// Diagnostic version of classifyDebugOrigin — logs detailed debug info.
/// All output at log.debug level (visible with --debug-log or equivalent).
pub fn classifyDebugOriginDiagnostic(func: c.LLVMValueRef, func_name: []const u8) ?SurfaceHint {
    const sp = c.LLVMGetSubprogram(func);
    if (@intFromPtr(sp) == 0) {
        log.debug("[DEBUG_ORIGIN] '{s}': NO subprogram (no debug info)", .{func_name});
        return null;
    }

    const file_ref = c.LLVMDIScopeGetFile(sp);
    if (@intFromPtr(file_ref) == 0) {
        log.debug("[DEBUG_ORIGIN] '{s}': has subprogram but NO DIFile", .{func_name});
        return null;
    }

    var dir_len: c_uint = 0;
    const dir_ptr = c.LLVMDIFileGetDirectory(file_ref, &dir_len);
    const max_path_len: c_uint = 8192;
    if (@intFromPtr(dir_ptr) == 0 or dir_len == 0 or dir_len > max_path_len) {
        log.debug("[DEBUG_ORIGIN] '{s}': DIFile directory empty or too long (len={d})", .{ func_name, dir_len });
        return null;
    }
    const dir = dir_ptr[0..dir_len];

    var name_len: c_uint = 0;
    const name_ptr = c.LLVMDIFileGetFilename(file_ref, &name_len);
    if (@intFromPtr(name_ptr) == 0 or name_len == 0 or name_len > max_path_len) {
        log.debug("[DEBUG_ORIGIN] '{s}': dir='{s}' but filename empty", .{ func_name, dir });
        return null;
    }
    const filename = name_ptr[0..name_len];

    const provenance = classifySourcePath(dir, filename);
    log.debug("[DEBUG_ORIGIN] '{s}': dir='{s}' file='{s}' => {s}", .{ func_name, dir, filename, @tagName(provenance) });

    return switch (provenance) {
        .user_code => .{
            .surface = .user_code,
            .confidence = .high,
            .reason = "source path in workspace",
        },
        .stdlib => .{
            .surface = .standard_library,
            .confidence = .high,
            .reason = "source path in standard library",
        },
        .dependency => .{
            .surface = .dependency,
            .confidence = .high,
            .reason = "source path in dependency registry",
        },
        .build_generated => .{
            .surface = .compiler_generated,
            .confidence = .medium,
            .reason = "source path in build output",
        },
        .unknown => {
            log.debug("[DEBUG_ORIGIN] '{s}': path matched UNKNOWN (no pattern matched)", .{func_name});
            return null;
        },
    };
}

/// Classify a source path into provenance categories.
///
/// Language-agnostic: matches path structure, not crate names.
pub fn classifySourcePath(dir: []const u8, filename: []const u8) SourceProvenance {
    _ = filename;

    // Rust standard library (provenance: compiler toolchain path)
    if (std.mem.indexOf(u8, dir, "/rustc/") != null) return .stdlib;
    if (std.mem.indexOf(u8, dir, "/.rustup/") != null) return .stdlib;
    if (std.mem.indexOf(u8, dir, "/rustlib/") != null) return .stdlib;
    if (std.mem.indexOf(u8, dir, "library/core/") != null) return .stdlib;
    if (std.mem.indexOf(u8, dir, "library/alloc/") != null) return .stdlib;
    if (std.mem.indexOf(u8, dir, "library/std/") != null) return .stdlib;
    if (std.mem.indexOf(u8, dir, "/src/libcore/") != null) return .stdlib;
    if (std.mem.indexOf(u8, dir, "/src/liballoc/") != null) return .stdlib;
    if (std.mem.indexOf(u8, dir, "/src/libstd/") != null) return .stdlib;

    // C++ standard library (provenance: system include path)
    if (std.mem.indexOf(u8, dir, "/include/c++/") != null) return .stdlib;
    if (std.mem.indexOf(u8, dir, "/usr/include/c++/") != null) return .stdlib;
    if (std.mem.indexOf(u8, dir, "/lib/gcc/") != null) return .stdlib;

    // Zig standard library
    if (std.mem.indexOf(u8, dir, "/lib/zig/") != null) return .stdlib;
    if (std.mem.indexOf(u8, dir, "zig/lib/std/") != null) return .stdlib;

    // Go standard library
    if (std.mem.indexOf(u8, dir, "/go/src/") != null) return .stdlib;

    // Swift standard library
    if (std.mem.indexOf(u8, dir, "/swift/lib/") != null) return .stdlib;

    // Python standard library
    if (std.mem.indexOf(u8, dir, "/lib/python") != null) return .stdlib;

    // Third-party dependencies (provenance: package manager registry)
    if (std.mem.indexOf(u8, dir, ".cargo/registry/") != null) return .dependency;
    if (std.mem.indexOf(u8, dir, "cargo/registry/") != null) return .dependency;

    // Build-generated code
    if (std.mem.indexOf(u8, dir, "/target/build/") != null) return .build_generated;
    if (std.mem.indexOf(u8, dir, "/build/out/") != null) return .build_generated;

    // User code (workspace paths — anything that doesn't match above)
    if (std.mem.indexOf(u8, dir, "/src/") != null) return .user_code;

    return .unknown;
}

// ============================================================================
// Tests
// ============================================================================

test "classifySourcePath - Rust stdlib paths" {
    try std.testing.expectEqual(SourceProvenance.stdlib, classifySourcePath("/rustc/a1b2c3d/library/core", "any.rs"));
    try std.testing.expectEqual(SourceProvenance.stdlib, classifySourcePath("/home/user/.rustup/toolchains/stable/library/alloc", "any.rs"));
    try std.testing.expectEqual(SourceProvenance.stdlib, classifySourcePath("/usr/lib/rustlib/src/library/std", "any.rs"));
    try std.testing.expectEqual(SourceProvenance.stdlib, classifySourcePath("/cargo/registry/src/library/core", "any.rs"));
    try std.testing.expectEqual(SourceProvenance.stdlib, classifySourcePath("/old/src/libcore/str.rs", "str.rs"));
    try std.testing.expectEqual(SourceProvenance.stdlib, classifySourcePath("/old/src/liballoc/alloc.rs", "alloc.rs"));
    try std.testing.expectEqual(SourceProvenance.stdlib, classifySourcePath("/old/src/libstd/io.rs", "io.rs"));
}

test "classifySourcePath - C++ STL paths" {
    try std.testing.expectEqual(SourceProvenance.stdlib, classifySourcePath("/usr/include/c++/12", "vector"));
    try std.testing.expectEqual(SourceProvenance.stdlib, classifySourcePath("/include/c++/v1", "string"));
    try std.testing.expectEqual(SourceProvenance.stdlib, classifySourcePath("/usr/lib/gcc/x86_64-linux-gnu/12/include", "stddef.h"));
}

test "classifySourcePath - Zig stdlib paths" {
    try std.testing.expectEqual(SourceProvenance.stdlib, classifySourcePath("/home/user/lib/zig/std", "mem.zig"));
    try std.testing.expectEqual(SourceProvenance.stdlib, classifySourcePath("/opt/zig/lib/std", "ArrayList.zig"));
}

test "classifySourcePath - Go stdlib paths" {
    try std.testing.expectEqual(SourceProvenance.stdlib, classifySourcePath("/usr/local/go/src/fmt", "print.go"));
}

test "classifySourcePath - dependency paths" {
    try std.testing.expectEqual(SourceProvenance.dependency, classifySourcePath("/home/user/.cargo/registry/src/index.crates.io-xxx/serde-1.0", "lib.rs"));
    try std.testing.expectEqual(SourceProvenance.dependency, classifySourcePath("/cargo/registry/src/serde-1.0", "lib.rs"));
}

test "classifySourcePath - build-generated paths" {
    try std.testing.expectEqual(SourceProvenance.build_generated, classifySourcePath("/project/target/build/out", "generated.rs"));
    try std.testing.expectEqual(SourceProvenance.build_generated, classifySourcePath("/project/build/out/derive", "derive.rs"));
}

test "classifySourcePath - user code paths" {
    try std.testing.expectEqual(SourceProvenance.user_code, classifySourcePath("/home/user/project/src/main.rs", "main.rs"));
    try std.testing.expectEqual(SourceProvenance.user_code, classifySourcePath("/workspace/myapp/src/lib.rs", "lib.rs"));
}

test "classifySourcePath - unknown paths" {
    try std.testing.expectEqual(SourceProvenance.unknown, classifySourcePath("/tmp", "test.rs"));
    try std.testing.expectEqual(SourceProvenance.unknown, classifySourcePath("/", "main.c"));
}

test "classifySourcePath - filename is not used for classification" {
    // Classification is based on directory path, not filename
    try std.testing.expectEqual(SourceProvenance.stdlib, classifySourcePath("/rustc/abc/library/core", "anything.xyz"));
    try std.testing.expectEqual(SourceProvenance.user_code, classifySourcePath("/home/user/src", "anything.xyz"));
}

test "classifySourcePath - ordering priority matters" {
    // /src/ matches user_code, but /rustc/ should match stdlib first
    try std.testing.expectEqual(SourceProvenance.stdlib, classifySourcePath("/rustc/abc/src/libcore", "lib.rs"));
    // cargo/registry/ matches dependency, not user_code even if /src/ is present
    try std.testing.expectEqual(SourceProvenance.dependency, classifySourcePath("/cargo/registry/src/serde", "lib.rs"));
}
