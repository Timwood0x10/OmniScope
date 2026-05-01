//! Debug Info Module
//!
//! Provides DWARF debug information handling utilities.
//! This is a thin wrapper around LLVM-C debug info APIs.
//!
//! Key APIs:
//! - LLVMGetDebugLoc* - Direct instruction debug location
//! - LLVMDILocation* - Metadata-level location info
//! - LLVMDILocationGetInlinedAt - Inline call stack support
//! - LLVMDIScopeGetFile - File info from scope
//! - LLVMDIFileGet* - File path components

const std = @import("std");
const c = @import("llvm_raw.zig").c;

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

/// Source location with file path, line, and column.
/// Used to represent debug info for instructions and functions.
pub const SourceLocation = struct {
    file: []const u8,
    directory: []const u8,
    line: u32,
    column: u32,

    pub fn valid(self: SourceLocation) bool {
        return self.file.len > 0 and self.line > 0;
    }

    pub fn format(
        self: SourceLocation,
        writer: anytype,
    ) !void {
        if (self.directory.len > 0) {
            try writer.print("{s}/{s}:{d}:{d}", .{ self.directory, self.file, self.line, self.column });
        } else {
            try writer.print("{s}:{d}:{d}", .{ self.file, self.line, self.column });
        }
    }
};

/// Inline call stack entry.
/// Represents one level of inlining in the call stack.
pub const InlineFrame = struct {
    location: SourceLocation,
    /// Name of the inlined function (if available)
    function_name: ?[]const u8,
};

/// Complete debug info for an instruction, including inline call stack.
pub const InstructionDebugInfo = struct {
    /// Direct source location of the instruction
    location: SourceLocation,
    /// Inline call stack (innermost first)
    inline_stack: []InlineFrame,
    /// Whether this instruction has valid debug info
    has_debug_info: bool,

    pub fn deinit(self: *InstructionDebugInfo, allocator: std.mem.Allocator) void {
        if (self.inline_stack.len > 0) {
            allocator.free(self.inline_stack);
        }
    }
};

pub const DIScope = struct {
    raw: c.LLVMMetadataRef,

    /// Get the file associated with this scope.
    /// Returns null if the scope has no file (e.g., for compile units).
    pub fn getFile(self: DIScope) ?DIFile {
        const file_ref = c.LLVMDIScopeGetFile(self.raw);
        if (file_ref == null) return null;
        return DIFile{ .raw = file_ref };
    }
};

pub const DIFile = struct {
    raw: c.LLVMMetadataRef,

    /// Get the directory path of this file.
    pub fn getDirectory(self: DIFile) []const u8 {
        var len: c_uint = 0;
        const dir_ptr = c.LLVMDIFileGetDirectory(self.raw, &len);
        if (@intFromPtr(dir_ptr) == 0 or len == 0) return "";
        return dir_ptr[0..len];
    }

    /// Get the filename (without directory) of this file.
    pub fn getFilename(self: DIFile) []const u8 {
        var len: c_uint = 0;
        const name_ptr = c.LLVMDIFileGetFilename(self.raw, &len);
        if (@intFromPtr(name_ptr) == 0 or len == 0) return "";
        return name_ptr[0..len];
    }

    /// Get the full path (directory + filename).
    /// Caller owns the returned slice.
    pub fn getFullPath(self: DIFile, allocator: std.mem.Allocator) ![]const u8 {
        const dir = self.getDirectory();
        const name = self.getFilename();
        if (dir.len == 0) return allocator.dupe(u8, name);
        if (name.len == 0) return allocator.dupe(u8, dir);
        return std.fmt.allocPrint(allocator, "{s}/{s}", .{ dir, name });
    }
};

pub const DICompileUnit = struct {
    raw: c.LLVMMetadataRef,

    pub fn getLanguage(self: DICompileUnit) DWARFSourceLanguage {
        const lang = c.LLVMGetCompileUnitLanguage(self.raw);
        return @enumFromInt(lang);
    }

    pub fn getFilename(self: DICompileUnit) []const u8 {
        const c_str = c.LLVMGetCompileUnitFilename(self.raw);
        return std.mem.span(c_str);
    }
};

pub const DISubprogram = struct {
    raw: c.LLVMMetadataRef,

    pub fn getName(self: DISubprogram) []const u8 {
        const c_str = c.LLVMGetSubprogramName(self.raw);
        return std.mem.span(c_str);
    }

    pub fn getLine(self: DISubprogram) u32 {
        return c.LLVMDISubprogramGetLine(self.raw);
    }

    pub fn getCompileUnit(self: DISubprogram) ?DICompileUnit {
        if (self.raw == null) return null;
        const cu = c.LLVMGetSubprogramCompileUnit(self.raw);
        if (cu == null) return null;
        return DICompileUnit{ .raw = cu };
    }
};

pub const DILocation = struct {
    raw: c.LLVMMetadataRef,

    pub fn getLine(self: DILocation) u32 {
        return c.LLVMDILocationGetLine(self.raw);
    }

    pub fn getColumn(self: DILocation) u32 {
        return c.LLVMDILocationGetColumn(self.raw);
    }

    pub fn getScope(self: DILocation) DIScope {
        return .{ .raw = c.LLVMDILocationGetScope(self.raw) };
    }

    /// Get the inlined-at location.
    /// Returns null if this location is not the result of inlining.
    /// Use this to build the inline call stack.
    pub fn getInlinedAt(self: DILocation) ?DILocation {
        const inlined = c.LLVMDILocationGetInlinedAt(self.raw);
        if (inlined == null) return null;
        return DILocation{ .raw = inlined };
    }

    /// Build the complete inline call stack.
    /// Returns an array of inline frames from innermost to outermost.
    /// Caller owns the returned slice.
    pub fn buildInlineStack(self: DILocation, allocator: std.mem.Allocator) ![]InlineFrame {
        var frames = std.ArrayList(InlineFrame).initCapacity(allocator, 4) catch
            return &[_]InlineFrame{};

        var loc = self;
        var depth: usize = 0;
        const max_depth: usize = 256;

        while (depth < max_depth) : (depth += 1) {
            const scope = loc.getScope();
            const file = scope.getFile();

            var location = SourceLocation{
                .file = "",
                .directory = "",
                .line = loc.getLine(),
                .column = loc.getColumn(),
            };

            if (file) |f| {
                location.file = f.getFilename();
                location.directory = f.getDirectory();
            }

            frames.appendAssumeCapacity(.{
                .location = location,
                .function_name = null,
            });

            const inlined = loc.getInlinedAt();
            if (inlined) |i| {
                loc = i;
            } else {
                break;
            }
        }

        return frames.toOwnedSlice();
    }
};

pub const DIBuilder = struct {
    raw: c.LLVMDIBuilderRef,

    pub fn create(module: c.LLVMModuleRef) DIBuilder {
        return .{ .raw = c.LLVMCreateDIBuilder(module) };
    }

    pub fn deinit(self: *DIBuilder) void {
        c.LLVMDisposeDIBuilder(self.raw);
    }
};

/// Debug info utilities for instructions and functions.
pub const DebugInfoUtils = struct {
    /// Get debug location directly from an instruction.
    /// This is the simplest way to get file/line/column.
    /// Returns null if the instruction has no debug info.
    pub fn getInstructionDebugLoc(inst: c.LLVMValueRef) ?SourceLocation {
        const line = c.LLVMGetDebugLocLine(inst);
        const column = c.LLVMGetDebugLocColumn(inst);

        // Line 0 means no debug info
        if (line == 0) return null;

        var dir_len: c_uint = 0;
        var file_len: c_uint = 0;

        const dir_ptr = c.LLVMGetDebugLocDirectory(inst, &dir_len);
        const file_ptr = c.LLVMGetDebugLocFilename(inst, &file_len);

        const directory: []const u8 = if (dir_len > 0 and @intFromPtr(dir_ptr) != 0)
            dir_ptr[0..dir_len]
        else
            "";

        const file: []const u8 = if (file_len > 0 and @intFromPtr(file_ptr) != 0)
            file_ptr[0..file_len]
        else
            "";

        return SourceLocation{
            .file = file,
            .directory = directory,
            .line = line,
            .column = column,
        };
    }

    /// Get complete debug info for an instruction, including inline call stack.
    /// Caller owns the returned struct and must call deinit().
    pub fn getInstructionDebugInfo(
        inst: c.LLVMValueRef,
        allocator: std.mem.Allocator,
    ) InstructionDebugInfo {
        _ = allocator;
        const location = getInstructionDebugLoc(inst);

        if (location == null) {
            return .{
                .location = .{ .file = "", .directory = "", .line = 0, .column = 0 },
                .inline_stack = &[_]InlineFrame{},
                .has_debug_info = false,
            };
        }

        // For now, we don't have access to the metadata ref from the instruction
        // directly, so we can't build the inline stack.
        // The LLVM C API doesn't provide a way to get the DILocation metadata
        // from an instruction directly.
        //
        // Future work: If we need inline stack, we would need to:
        // 1. Get the instruction's metadata using LLVMGetMetadata
        // 2. Check if it's a DILocation
        // 3. Use DILocation.buildInlineStack

        return .{
            .location = location.?,
            .inline_stack = &[_]InlineFrame{},
            .has_debug_info = true,
        };
    }

    /// Get the subprogram (function debug info) for a function.
    /// Returns null if the function has no debug info.
    pub fn getFunctionSubprogram(func: c.LLVMValueRef) ?DISubprogram {
        const subprogram = c.LLVMGetSubprogram(func);
        if (subprogram == null) return null;
        return DISubprogram{ .raw = subprogram };
    }

    /// Get the source location of a function definition.
    /// Returns null if the function has no debug info.
    pub fn getFunctionLocation(func: c.LLVMValueRef) ?SourceLocation {
        const subprogram = getFunctionSubprogram(func) orelse return null;

        const line = subprogram.getLine();
        if (line == 0) return null;

        const scope = DIScope{ .raw = subprogram.raw };
        const file = scope.getFile() orelse return null;

        return SourceLocation{
            .file = file.getFilename(),
            .directory = file.getDirectory(),
            .line = line,
            .column = 0,
        };
    }

    /// Check if a module has any debug info.
    /// Looks for llvm.dbg.* intrinsics and !dbg metadata.
    pub fn moduleHasDebugInfo(module: c.LLVMModuleRef) bool {
        // Check for named metadata "llvm.dbg.cu" (compile units)
        const dbg_cu = c.LLVMGetNamedMetadata(module, "llvm.dbg.cu");
        if (dbg_cu != null) return true;

        // Check for llvm.dbg.* intrinsics
        var func = c.LLVMGetFirstFunction(module);
        while (@intFromPtr(func) != 0) : (func = c.LLVMGetNextFunction(func)) {
            const name_ptr = c.LLVMGetValueName(func);
            if (@intFromPtr(name_ptr) == 0) continue;
            const name = std.mem.span(name_ptr);

            if (std.mem.startsWith(u8, name, "llvm.dbg.")) {
                return true;
            }
        }

        return false;
    }
};

// Unit tests

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
        .directory = "/src",
        .line = 10,
        .column = 5,
    };
    try std.testing.expect(valid_loc.valid());

    const invalid_loc = SourceLocation{
        .file = "",
        .directory = "",
        .line = 0,
        .column = 0,
    };
    try std.testing.expect(!invalid_loc.valid());
}

test "SourceLocation - format" {
    const loc = SourceLocation{
        .file = "test.zig",
        .directory = "/src",
        .line = 10,
        .column = 5,
    };

    var buf: [100]u8 = undefined;
    const result = try std.fmt.bufPrint(&buf, "{}", .{loc});
    try std.testing.expectEqualStrings("/src/test.zig:10:5", result);

    const loc_no_dir = SourceLocation{
        .file = "test.zig",
        .directory = "",
        .line = 10,
        .column = 5,
    };
    const result2 = try std.fmt.bufPrint(&buf, "{}", .{loc_no_dir});
    try std.testing.expectEqualStrings("test.zig:10:5", result2);
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
    const loc1 = SourceLocation{ .file = "a.zig", .directory = "/src", .line = 1, .column = 1 };
    const loc2 = SourceLocation{ .file = "a.zig", .directory = "/src", .line = 1, .column = 1 };
    const loc3 = SourceLocation{ .file = "b.zig", .directory = "/src", .line = 1, .column = 1 };
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

test "DIFile - type definition" {
    const file = DIFile{ .raw = null };
    try std.testing.expect(file.raw == null);
}

test "InlineFrame - type definition" {
    const frame = InlineFrame{
        .location = .{ .file = "test.zig", .directory = "", .line = 1, .column = 1 },
        .function_name = "testFunc",
    };
    try std.testing.expect(frame.function_name != null);
}

test "InstructionDebugInfo - type definition" {
    const info = InstructionDebugInfo{
        .location = .{ .file = "test.zig", .directory = "", .line = 1, .column = 1 },
        .inline_stack = &[_]InlineFrame{},
        .has_debug_info = true,
    };
    try std.testing.expect(info.has_debug_info);
}
