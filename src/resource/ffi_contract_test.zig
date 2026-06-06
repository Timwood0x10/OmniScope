//! Tests for FFI Contract Data layer.
//!
//! Validates that the contract data re-exports from ffi_contract_data.zig
//! are consistent with the underlying modules.

const std = @import("std");
const FFIContractDB = @import("ffi_contract_db.zig").FFIContractDB;
const PairMatchResult = @import("ffi_contract_db.zig").PairMatchResult;

test "ffi_contract_data - re-exports match source modules" {
    const data = @import("ffi_contract_data.zig");
    const db_data = @import("ffi_contract_db_data.zig");
    const db = @import("ffi_contract_db.zig");

    // Verify type re-exports match the original definitions
    try std.testing.expectEqual(db.OwnershipModel, data.OwnershipModel);
    try std.testing.expectEqual(db.PairMatchResult, data.PairMatchResult);
    try std.testing.expectEqual(db.AllocPairRule, data.AllocPairRule);
    try std.testing.expectEqual(db.ManagedTypeInfo, data.ManagedTypeInfo);
    try std.testing.expectEqual(db.LibraryContract, data.LibraryContract);

    // Verify builtinLibraries function is the same
    try std.testing.expectEqual(@TypeOf(data.builtinLibraries), @TypeOf(db_data.builtinLibraries));
}

test "ffi_contract_data - builtinLibraries returns valid data" {
    const data = @import("ffi_contract_data.zig");
    const libs = data.builtinLibraries();

    // Should have at least the expected libraries
    try std.testing.expect(libs.len >= 9);

    // Verify each library has a name
    for (libs) |lib| {
        try std.testing.expect(lib.name.len > 0);
    }
}

test "ffi_contract_data - FFIContractDB works with re-exported types" {
    var db = try FFIContractDB.init(std.testing.allocator);
    defer db.deinit();

    // Basic queries through the re-exported API
    try std.testing.expect(db.shouldReportLeak("SSL_CTX_new"));
    try std.testing.expect(!db.shouldReportLeak("JSObjectMake"));
    try std.testing.expectEqual(PairMatchResult.valid_pair, db.isValidRelease("SSL_new", "SSL_free"));
    try std.testing.expectEqual(PairMatchResult.mismatch, db.isValidRelease("SSL_new", "BIO_free"));
}
