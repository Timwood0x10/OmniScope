//! FFI Contract Data — Types and built-in library contract definitions.
//!
//! Centralizes the type definitions and built-in contract data for FFI
//! lifecycle analysis. This file serves as the single source of truth for
//! contract data types and the built-in library rules.
//!
//! Usage:
//!   const data = @import("ffi_contract_data.zig");
//!   const libs = data.builtinLibraries();
//!   const model = data.OwnershipModel.caller;

pub const OwnershipModel = @import("ffi_contract_db.zig").OwnershipModel;
pub const PairMatchResult = @import("ffi_contract_db.zig").PairMatchResult;
pub const AllocPairRule = @import("ffi_contract_db.zig").AllocPairRule;
pub const ManagedTypeInfo = @import("ffi_contract_db.zig").ManagedTypeInfo;
pub const LibraryContract = @import("ffi_contract_db.zig").LibraryContract;
pub const builtinLibraries = @import("ffi_contract_db_data.zig").builtinLibraries;
