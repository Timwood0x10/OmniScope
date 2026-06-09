//! LLVM Subprogram Path Classification
//!
//! Classifies functions by their LLVM DISubprogram debug metadata source path.
//! Uses actual source file locations from debug info to distinguish
//! standard library code from user code.

const std = @import("std");
const c = @import("../ir/llvm_raw.zig").c;
const debug_info = @import("../ir/debug_info.zig");
const zone_types = @import("../types/zone_types.zig");
const ZoneKind = zone_types.ZoneKind;

/// Classify a function by its LLVM DISubprogram debug metadata source path.
///
/// Checks the source file location from debug info to determine if the function
/// comes from standard library vs user code. This is significantly more accurate
/// than name-based heuristics, especially for mangled names (Rust _ZN*, C++ _Z*).
///
/// Returns:
///   ZoneKind if classification succeeded via debug path, null otherwise
pub fn classifyBySubprogramPath(func: c.LLVMValueRef) ?ZoneKind {
    const subprogram = debug_info.DebugInfoUtils.getFunctionSubprogram(func) orelse return null;

    const file_ref = c.LLVMDIScopeGetFile(subprogram.raw);
    if (@intFromPtr(file_ref) == 0) return null;

    var filename_len: c_uint = undefined;
    const filename_ptr = c.LLVMDIFileGetFilename(file_ref, &filename_len);
    if (@intFromPtr(filename_ptr) == 0 or filename_len == 0) return null;

    const max_path_len: c_uint = 4096;
    if (filename_len > max_path_len) return null;
    if (filename_ptr[0] == 0) return null;

    const filename = filename_ptr[0..filename_len];

    const rust_stdlib_paths = [_][]const u8{
        "/rustc/",         "/.rustup/",        "/rustlib/",
        "library/core/",   "library/alloc/",   "library/std/",
        "/src/libcore/",   "/src/liballoc/",   "/src/libstd/",
        "cargo/registry/", ".cargo/registry/",
    };
    for (rust_stdlib_paths) |pat| {
        if (std.mem.indexOf(u8, filename, pat) != null) return .runtime_internal;
    }

    const zig_stdlib_paths = [_][]const u8{
        "/zig/lib/std/", "/zig/lib/builtin/",
        "lib/std/",      "lib/builtin/",
    };
    for (zig_stdlib_paths) |pat| {
        if (std.mem.indexOf(u8, filename, pat) != null) return .runtime_internal;
    }

    const go_runtime_paths = [_][]const u8{
        "/usr/local/go/src/runtime/", "/go/src/runtime/",
        "go/src/runtime/",            "_cgo_gotypes.go",
    };
    for (go_runtime_paths) |pat| {
        if (std.mem.indexOf(u8, filename, pat) != null) return .runtime_internal;
    }

    const system_paths = [_][]const u8{
        "/usr/include/", "/usr/local/include/",
        "/sysroot/",     "/llvm-project/",
        "/libcxx/",
    };
    for (system_paths) |pat| {
        if (std.mem.indexOf(u8, filename, pat) != null) return .safe;
    }

    if (std.mem.indexOf(u8, filename, "_cgo_") != null) return .runtime_internal;

    return null;
}
