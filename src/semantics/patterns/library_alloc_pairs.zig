//! R-7: Library-Level Allocator Pairs Detector
//!
//! Covers non-POSIX library allocators that have their own acquire/release
//! pairs. These are NOT standard POSIX syscalls — they are library-specific
//! APIs documented in man pages / API references.
//!
//! R-4 covers POSIX syscalls (unlink/close/socket etc.).
//! R-7 covers third-party library allocators (mimalloc/zlib/openssl/sqlite/
//! Go cgo/Python CFFI/JNI/Zig allocator). The two tables are complementary.
//!
//! When cross_language_free detection hits a library_release function,
//! it should NOT report — this is a legitimate in-library deallocation.

const std = @import("std");
const c = @import("../../ir/llvm_raw.zig").c;
const llvm_safe = @import("../../ir/llvm_safe.zig");
const SemanticTree = @import("../semantic_tree.zig").SemanticTree;
const SemanticKind = @import("../semantic_tree.zig").SemanticKind;
const DiagnosticWriter = @import("../../pass/pass.zig").DiagnosticWriter;

/// Effect classification for library allocator functions.
pub const LibraryEffect = enum {
    acquire, // Allocates/acquires a resource
    release, // Releases/frees a resource
    borrow, // Borrows a reference (no ownership change)
    conditional_release, // Releases only if refcount drops to zero
};

/// Language classification.
pub const LibraryLang = enum {
    c,
    rust,
    go,
    python,
    java,
    zig,
    any, // Language-independent
};

/// A single entry in the library allocator pair table.
const LibraryAllocEntry = struct {
    name: []const u8,
    language: LibraryLang,
    effect: LibraryEffect,
};

/// The library allocator pair table.
/// Each entry maps a function name to its semantic effect.
/// Source: ir.md §9 (manually curated from real .ll files).
const TABLE = [_]LibraryAllocEntry{
    // ── mimalloc (bun's underlying allocator) ──
    .{ .name = "mi_malloc", .language = .c, .effect = .acquire },
    .{ .name = "mi_free", .language = .c, .effect = .release },
    .{ .name = "mi_realloc", .language = .c, .effect = .acquire },
    .{ .name = "mi_zalloc", .language = .c, .effect = .acquire },
    .{ .name = "mi_heap_destroy", .language = .c, .effect = .conditional_release },
    .{ .name = "mi_heap_malloc", .language = .c, .effect = .acquire },
    .{ .name = "mi_heap_realloc", .language = .c, .effect = .acquire },
    .{ .name = "mi_heap_zalloc", .language = .c, .effect = .acquire },
    .{ .name = "mi_heap_free", .language = .c, .effect = .release },

    // ── zlib ──
    .{ .name = "inflateInit_", .language = .c, .effect = .acquire },
    .{ .name = "inflateEnd", .language = .c, .effect = .release },
    .{ .name = "deflateInit_", .language = .c, .effect = .acquire },
    .{ .name = "deflateEnd", .language = .c, .effect = .release },
    .{ .name = "inflateReset", .language = .c, .effect = .borrow },
    .{ .name = "deflateReset", .language = .c, .effect = .borrow },

    // ── openssl ──
    .{ .name = "EVP_CIPHER_CTX_new", .language = .c, .effect = .acquire },
    .{ .name = "EVP_CIPHER_CTX_free", .language = .c, .effect = .release },
    .{ .name = "EVP_MD_CTX_new", .language = .c, .effect = .acquire },
    .{ .name = "EVP_MD_CTX_free", .language = .c, .effect = .release },
    .{ .name = "BIO_new", .language = .c, .effect = .acquire },
    .{ .name = "BIO_free", .language = .c, .effect = .release },
    .{ .name = "BIO_free_all", .language = .c, .effect = .release },
    .{ .name = "RSA_new", .language = .c, .effect = .acquire },
    .{ .name = "RSA_free", .language = .c, .effect = .release },
    .{ .name = "BN_new", .language = .c, .effect = .acquire },
    .{ .name = "BN_free", .language = .c, .effect = .release },
    .{ .name = "SSL_CTX_new", .language = .c, .effect = .acquire },
    .{ .name = "SSL_CTX_free", .language = .c, .effect = .release },
    .{ .name = "X509_new", .language = .c, .effect = .acquire },
    .{ .name = "X509_free", .language = .c, .effect = .release },

    // ── sqlite ──
    .{ .name = "sqlite3_open", .language = .c, .effect = .acquire },
    .{ .name = "sqlite3_open_v2", .language = .c, .effect = .acquire },
    .{ .name = "sqlite3_close", .language = .c, .effect = .release },
    .{ .name = "sqlite3_close_v2", .language = .c, .effect = .release },
    .{ .name = "sqlite3_prepare_v2", .language = .c, .effect = .acquire },
    .{ .name = "sqlite3_prepare_v3", .language = .c, .effect = .acquire },
    .{ .name = "sqlite3_finalize", .language = .c, .effect = .release },
    .{ .name = "sqlite3_free", .language = .c, .effect = .release },
    .{ .name = "sqlite3_malloc", .language = .c, .effect = .acquire },
    .{ .name = "sqlite3_realloc", .language = .c, .effect = .acquire },

    // ── Go cgo ──
    .{ .name = "_cgo_allocate", .language = .go, .effect = .acquire },
    .{ .name = "_cgo_free", .language = .go, .effect = .release },
    .{ .name = "_Cfunc_GoMalloc", .language = .go, .effect = .acquire },
    .{ .name = "_Cfunc_GoFree", .language = .go, .effect = .release },

    // ── Python CFFI ──
    .{ .name = "PyBytes_FromStringAndSize", .language = .python, .effect = .acquire },
    .{ .name = "PyTuple_New", .language = .python, .effect = .acquire },
    .{ .name = "PyList_New", .language = .python, .effect = .acquire },
    .{ .name = "PyDict_New", .language = .python, .effect = .acquire },
    .{ .name = "Py_DECREF", .language = .python, .effect = .conditional_release },
    .{ .name = "Py_XDECREF", .language = .python, .effect = .conditional_release },
    .{ .name = "Py_CLEAR", .language = .python, .effect = .conditional_release },
    .{ .name = "PyList_GetItem", .language = .python, .effect = .borrow },
    .{ .name = "PyBytes_AsString", .language = .python, .effect = .borrow },

    // ── JNI ──
    .{ .name = "NewGlobalRef", .language = .java, .effect = .acquire },
    .{ .name = "NewLocalRef", .language = .java, .effect = .acquire },
    .{ .name = "NewStringUTF", .language = .java, .effect = .acquire },
    .{ .name = "NewByteArray", .language = .java, .effect = .acquire },
    .{ .name = "DeleteGlobalRef", .language = .java, .effect = .release },
    .{ .name = "DeleteLocalRef", .language = .java, .effect = .release },
    .{ .name = "GetStringUTFChars", .language = .java, .effect = .borrow },
    .{ .name = "ReleaseStringUTFChars", .language = .java, .effect = .release },
    .{ .name = "GetPrimitiveArrayCritical", .language = .java, .effect = .borrow },
    .{ .name = "ReleasePrimitiveArrayCritical", .language = .java, .effect = .release },

    // ── Zig allocator ──
    .{ .name = "zig_allocator_allocImpl", .language = .zig, .effect = .acquire },
    .{ .name = "zig_allocator_freeImpl", .language = .zig, .effect = .release },
};

/// Detect library allocator pair patterns and write to SRT.
/// For each call instruction, checks if the callee matches a table entry.
/// Release/conditional_release → write SRT .library_release
/// Acquire → write SRT .allocation (for leak detection)
/// Borrow → write SRT .provenance (for borrow tracking)
pub fn detect(
    module: c.LLVMModuleRef,
    srt: *SemanticTree,
    diag: *DiagnosticWriter,
) !void {
    _ = diag;

    var func = c.LLVMGetFirstFunction(module);
    while (@intFromPtr(func) != 0) : (func = c.LLVMGetNextFunction(func)) {
        if (c.LLVMIsDeclaration(func) != 0) continue;

        var bb = c.LLVMGetFirstBasicBlock(func);
        while (@intFromPtr(bb) != 0) : (bb = c.LLVMGetNextBasicBlock(bb)) {
            var inst = c.LLVMGetFirstInstruction(bb);
            while (@intFromPtr(inst) != 0) : (inst = c.LLVMGetNextInstruction(inst)) {
                if (!llvm_safe.isCallOrInvoke(c.LLVMGetInstructionOpcode(inst))) continue;

                const callee_name = getCalleeName(inst) orelse continue;
                const entry = lookupTable(callee_name) orelse continue;

                const kind: SemanticKind = switch (entry.effect) {
                    .release, .conditional_release => .library_release,
                    .acquire => .allocation,
                    .borrow => .provenance,
                };

                const evidence = switch (entry.effect) {
                    .release => "library release",
                    .conditional_release => "library conditional release",
                    .acquire => "library acquire",
                    .borrow => "library borrow",
                };

                try srt.recordResolution(
                    @intFromPtr(inst),
                    kind,
                    0.95,
                    "R-7 lib alloc",
                    evidence,
                );
            }
        }
    }
}

/// Look up a function name in the library allocator pair table.
/// Uses exact match (not substring) to avoid false positives.
pub fn lookupTable(name: []const u8) ?LibraryAllocEntry {
    for (TABLE) |entry| {
        if (std.mem.eql(u8, name, entry.name)) return entry;
    }
    return null;
}

/// Check if a function name is a library release function.
pub fn isLibraryRelease(name: []const u8) bool {
    const entry = lookupTable(name) orelse return false;
    return entry.effect == .release or entry.effect == .conditional_release;
}

/// Get callee name from a call instruction.
fn getCalleeName(inst: c.LLVMValueRef) ?[]const u8 {
    const called_val = c.LLVMGetCalledValue(inst);
    if (@intFromPtr(called_val) == 0) return null;
    const name_raw = c.LLVMGetValueName(called_val);
    if (@intFromPtr(name_raw) == 0) return null;
    const name = std.mem.sliceTo(name_raw, 0);
    if (name.len == 0) return null;
    return name;
}
