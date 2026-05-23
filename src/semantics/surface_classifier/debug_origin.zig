//! Surface Classifier — Layer 2: Debug Origin / Source Path Provenance
//!
//! Classifies function origin from DISubprogram → DIFile source path.
//! This replaces name-based whitelisting with provenance matching.
//!
//! Key insight: Rust stdlib always lives at /rustc/<hash>/library/ regardless
//! of version or project. C++ STL is at /include/c++/. No crate names needed.

const std = @import("std");
const c = @import("../../ir/llvm_raw.zig").c;
const SurfaceHint = @import("surface_classifier.zig").SurfaceHint;
const FunctionSurface = @import("surface_classifier.zig").FunctionSurface;

/// Source provenance determined from DIFile path.
const SourceProvenance = enum {
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
