const std = @import("std");
const Severity = @import("../diag/issue.zig").Severity;

pub const ABIViolation = enum(u8) {
    packed_struct_ffi,
    alignment_mismatch,
    size_mismatch,
    variadic_type_mismatch,
    endianness_risk,
};

pub fn abiViolationSeverity(violation: ABIViolation) Severity {
    return switch (violation) {
        .packed_struct_ffi => .critical,
        .alignment_mismatch => .high,
        .size_mismatch => .high,
        .variadic_type_mismatch => .medium,
        .endianness_risk => .medium,
    };
}

pub const ABIIssue = struct {
    violation: ABIViolation,
    confidence: f32,
    func_name: []const u8,
    callee_name: []const u8,
    description: []const u8,
    instruction_line: ?u32 = null,
};

pub const ABIStats = struct {
    total_functions_analyzed: u32 = 0,
    extern_calls_checked: u32 = 0,
    packed_struct_violations: u32 = 0,
    alignment_mismatches: u32 = 0,
    size_mismatches: u32 = 0,
    variadic_issues: u32 = 0,
    endianness_warnings: u32 = 0,

    pub fn formatSummary(self: ABIStats, writer: anytype) !void {
        try writer.writeAll("\n╔══════════════════════════════════════╗\n");
        try writer.writeAll("║     ABI MISMATCH DETECTOR SUMMARY    ║\n");
        try writer.writeAll("╠══════════════════════════════════════╣\n");
        try writer.print("║  Functions analyzed:      {d:>8}     ║\n", .{self.total_functions_analyzed});
        try writer.print("║  Extern calls checked:    {d:>8}     ║\n", .{self.extern_calls_checked});
        try writer.print("║  Packed struct violations: {d:>8}     ║\n", .{self.packed_struct_violations});
        try writer.print("║  Alignment mismatches:    {d:>8}     ║\n", .{self.alignment_mismatches});
        try writer.print("║  Size mismatches:         {d:>8}     ║\n", .{self.size_mismatches});
        try writer.print("║  Variadic issues:         {d:>8}     ║\n", .{self.variadic_issues});
        try writer.print("║  Endianness warnings:     {d:>8}     ║\n", .{self.endianness_warnings});
        try writer.writeAll("╚══════════════════════════════════════╝\n");
    }
};

const PACKED_STRUCT_PATTERNS = &[_][]const u8{
    "packed struct",
    "packed union",
    "extern struct",
    "bit_field",
    "__attribute__((packed))",
};

const VARIADIC_FUNCTIONS = &[_][]const u8{
    "printf",         "fprintf", "sprintf", "snprintf",
    "scanf",          "fscanf",  "sscanf",  "openlog",
    "syslog",         "execl",   "execle",  "execlp",
    "pthread_create",
};

const ENDIAN_SENSITIVE_TYPES = &[_][]const u8{
    "u16le", "u16be", "u32le", "u32be",
    "u64le", "u64be", "i16le", "i16be",
    "i32le", "i32be", "i64le", "i64be",
};

pub fn isPackedStructType(type_name: []const u8) bool {
    for (PACKED_STRUCT_PATTERNS) |pattern| {
        if (std.mem.indexOf(u8, type_name, pattern) != null) return true;
    }
    return false;
}

pub fn isVariadicFunction(callee_name: []const u8) bool {
    for (VARIADIC_FUNCTIONS) |fn_name| {
        if (std.mem.eql(u8, callee_name, fn_name)) return true;
    }
    return false;
}

pub fn isEndianSensitive(type_name: []const u8) bool {
    for (ENDIAN_SENSITIVE_TYPES) |t| {
        if (std.mem.indexOf(u8, type_name, t) != null) return true;
    }
    return false;
}

pub fn isExternCall(callee_name: []const u8) bool {
    if (callee_name.len == 0) return false;

    if (std.mem.startsWith(u8, callee_name, "c_") or
        std.mem.startsWith(u8, callee_name, "C."))
    {
        return true;
    }

    const common_extern_prefixes = [_][]const u8{
        "SDL_",     "GL_",     "glfw", "curl",  "openssl",
        "pthread_", "signal(", "mmap", "ioctl",
    };
    for (common_extern_prefixes) |prefix| {
        if (std.mem.startsWith(u8, callee_name, prefix)) return true;
    }

    return false;
}
