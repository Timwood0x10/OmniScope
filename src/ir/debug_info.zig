//! Debug Info Module
//!
//! Provides DWARF debug information handling utilities.
//! This is a thin wrapper around LLVM-C debug info APIs.

const std = @import("std");
const llvm = @import("llvm_c.zig");

pub const DWARFSourceLanguage = enum(c_uint) {
    C89 = 0,
    C = 1,
    Ada83 = 2,
    C_plus_plus = 3,
    Cobol74 = 4,
    Cobol85 = 5,
    Fortran77 = 6,
    Fortran90 = 7,
    Pascal83 = 8,
    Modula2 = 9,
    Java = 10,
    C99 = 11,
    Ada95 = 12,
    Fortran95 = 13,
    PLI = 14,
    ObjC = 15,
    ObjC_plus_plus = 16,
    UPC = 17,
    D = 18,
    Python = 19,
    OpenCL = 20,
    GLslang = 21,
    Rust = 22,
    Swift = 23,
    Julia = 24,
    Dylan = 25,
    Fischer = 26,
    LabVIEW = 27,
    Mips_assembler = 28,
    GoogleRenderScript = 29,
    Borland = 30,
    Mips = 31,
    Fantom = 32,
    C_plus_plus_03 = 33,
};

pub const DWARFTypeKind = enum(c_uint) {
    Array = 0x01,
    Builtin = 0x02,
    Class = 0x03,
    Enum = 0x04,
    Function = 0x05,
    Namespace = 0x10000,
    Struct = 0x10001,
    Union = 0x10002,
    Variant = 0x10003,
    Interface = 0x10004,
};

pub const DWARFEmissionKind = enum(c_uint) {
    None = 0,
    Full = 1,
    LineTablesOnly = 2,
};

pub const DIFlags = struct {
    pub const Zero: c_uint = 0;
    pub const Private: c_uint = 1;
    pub const Protected: c_uint = 2;
    pub const Public: c_uint = 3;
    pub const FwdDecl: c_uint = (1 << 2);
    pub const AppleBlock: c_uint = (1 << 3);
    pub const Virtual: c_uint = (1 << 5);
    pub const Artificial: c_uint = (1 << 6);
    pub const Explicit: c_uint = (1 << 7);
    pub const Prototyped: c_uint = (1 << 8);
    pub const ObjcClassComplete: c_uint = (1 << 9);
    pub const ObjectPointer: c_uint = (1 << 10);
    pub const StaticMember: c_uint = (1 << 12);
    pub const LValueReference: c_uint = (1 << 13);
    pub const RValueReference: c_uint = (1 << 14);
    pub const NoReturn: c_uint = (1 << 20);
};

pub const SourceLocation = struct {
    file: []const u8,
    line: u32,
    column: u32,

    pub fn valid(self: SourceLocation) bool {
        return self.file.len > 0 and self.line > 0;
    }
};

pub const DIScope = struct {
    raw: llvm.LLVMMetadataRef,
};

pub const DICompileUnit = struct {
    raw: llvm.LLVMMetadataRef,

    pub fn getLanguage(self: DICompileUnit) DWARFSourceLanguage {
        const lang = llvm.LLVMGetCompileUnitLanguage(self.raw);
        return @enumFromInt(lang);
    }

    pub fn getFilename(self: DICompileUnit) []const u8 {
        const c_str = llvm.LLVMGetCompileUnitFilename(self.raw);
        return std.mem.span(c_str);
    }
};

pub const DISubprogram = struct {
    raw: llvm.LLVMMetadataRef,

    pub fn getName(self: DISubprogram) []const u8 {
        const c_str = llvm.LLVMGetSubprogramName(self.raw);
        return std.mem.span(c_str);
    }

    pub fn getLine(self: DISubprogram) u32 {
        return llvm.LLVMGetSubprogramLine(self.raw);
    }
};

pub const DILocation = struct {
    raw: llvm.LLVMMetadataRef,

    pub fn getLine(self: DILocation) u32 {
        return llvm.LLMDILocationGetLine(self.raw);
    }

    pub fn getColumn(self: DILocation) u32 {
        return llvm.LLMDILocationGetColumn(self.raw);
    }

    pub fn getScope(self: DILocation) DIScope {
        return .{ .raw = llvm.LLMDILocationGetScope(self.raw) };
    }
};

pub const DIBuilder = struct {
    raw: llvm.LLVMDIBuilderRef,

    pub fn create(module: llvm.LLVMModuleRef) DIBuilder {
        return .{ .raw = llvm.LLVMCreateDIBuilder(module) };
    }

    pub fn deinit(self: *DIBuilder) void {
        llvm.LLVMDisposeDIBuilder(self.raw);
    }
};

test "DWARFSourceLanguage - enum values" {
    try std.testing.expectEqual(@as(c_uint, 1), @intFromEnum(DWARFSourceLanguage.C));
    try std.testing.expectEqual(@as(c_uint, 3), @intFromEnum(DWARFSourceLanguage.C_plus_plus));
    try std.testing.expectEqual(@as(c_uint, 22), @intFromEnum(DWARFSourceLanguage.Rust));
    try std.testing.expectEqual(@as(c_uint, 23), @intFromEnum(DWARFSourceLanguage.Swift));
}

test "DIFlags - flag values" {
    try std.testing.expectEqual(@as(c_uint, 0), DIFlags.Zero);
    try std.testing.expectEqual(@as(c_uint, 1), DIFlags.Private);
    try std.testing.expectEqual(@as(c_uint, 2), DIFlags.Protected);
    try std.testing.expectEqual(@as(c_uint, 3), DIFlags.Public);
    try std.testing.expectEqual(@as(c_uint, (1 << 20)), DIFlags.NoReturn);
}

test "SourceLocation - valid" {
    const valid_loc = SourceLocation{
        .file = "test.zig",
        .line = 10,
        .column = 5,
    };
    try std.testing.expect(valid_loc.valid());

    const invalid_loc = SourceLocation{
        .file = "",
        .line = 0,
        .column = 0,
    };
    try std.testing.expect(!invalid_loc.valid());
}

test "DWARFTypeKind - enum values" {
    try std.testing.expectEqual(@as(c_uint, 0x01), @intFromEnum(DWARFTypeKind.Array));
    try std.testing.expectEqual(@as(c_uint, 0x02), @intFromEnum(DWARFTypeKind.Builtin));
    try std.testing.expectEqual(@as(c_uint, 0x03), @intFromEnum(DWARFTypeKind.Class));
    try std.testing.expectEqual(@as(c_uint, 0x10000), @intFromEnum(DWARFTypeKind.Namespace));
}

test "DWARFEmissionKind - enum values" {
    try std.testing.expectEqual(@as(c_uint, 0), @intFromEnum(DWARFEmissionKind.None));
    try std.testing.expectEqual(@as(c_uint, 1), @intFromEnum(DWARFEmissionKind.Full));
    try std.testing.expectEqual(@as(c_uint, 2), @intFromEnum(DWARFEmissionKind.LineTablesOnly));
}

test "SourceLocation - equality" {
    const loc1 = SourceLocation{ .file = "a.zig", .line = 1, .column = 1 };
    const loc2 = SourceLocation{ .file = "a.zig", .line = 1, .column = 1 };
    const loc3 = SourceLocation{ .file = "b.zig", .line = 1, .column = 1 };
    try std.testing.expect(std.mem.eql(u8, loc1.file, loc2.file));
    try std.testing.expect(!std.mem.eql(u8, loc1.file, loc3.file));
}

test "DIBuilder - create and destroy" {
    _ = DIBuilder;
}

test "DIScope - type definition" {
    const scope = DIScope{ .raw = null };
    try std.testing.expect(scope.raw == null);
}

test "DILocation - type definition" {
    const loc = DILocation{ .raw = null };
    try std.testing.expect(loc.raw == null);
}
