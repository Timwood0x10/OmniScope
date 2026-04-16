//! LLVM-C API Raw Bindings (Auto-generated via @cImport)
//!
//! This layer provides direct access to LLVM C API via Zig's @cImport.
//! DO NOT use this layer directly - use llvm_safe.zig instead.

const std = @import("std");

// Import LLVM C headers
pub const c = @cImport({
    @cInclude("llvm-c/Core.h");
    @cInclude("llvm-c/IRReader.h");
    @cInclude("llvm-c/BitReader.h");
    @cInclude("llvm-c/Analysis.h");
    @cInclude("llvm-c/Target.h");
});
