//! Pass struct type definitions extracted from pass_types.zig.
//!
//! Contains all non-PassContext type definitions: pass kinds, edges,
//! call sites, allocation tracking, and diagnostic utilities.

const std = @import("std");
const Allocator = std.mem.Allocator;
const log = @import("../common/log.zig");
const c = @import("../ir/llvm_raw.zig").c;

const NoiseSeverity = @import("../semantics/noise_filter.zig").Severity;
const DiagSeverity = @import("../diag/issue.zig").Severity;

/// Pass kind classification
pub const PassKind = enum {
    foundation,
    analysis,
    plugin,
};

/// R8.2: Cross-language call edge extracted by CallGraphPass.
pub const CrossLangEdge = struct {
    caller_name: []const u8,
    callee_name: []const u8,
    caller_lang: @import("../diag/issue.zig").FFIBoundary.Language,
    callee_lang: @import("../diag/issue.zig").FFIBoundary.Language,
    is_ffi_boundary: bool,
    ptr_args: []const u32,
};

/// A single call site record in the shared index.
pub const CallSite = struct {
    caller_func: u64,
    inst: u64,
};

/// Shared callee → call_sites index for O(1) lookup.
pub const CallSiteIndex = struct {
    map: std.StringHashMap(std.ArrayList(CallSite)),
    allocator: Allocator,

    pub fn init(allocator: Allocator) CallSiteIndex {
        return .{ .map = std.StringHashMap(std.ArrayList(CallSite)).init(allocator), .allocator = allocator };
    }

    pub fn deinit(self: *CallSiteIndex) void {
        var iter = self.map.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.deinit(self.allocator);
        }
        self.map.deinit();
    }

    pub fn addCall(self: *CallSiteIndex, allocator: Allocator, callee_name: []const u8, caller_func: u64, inst: u64) !void {
        const gop = try self.map.getOrPut(callee_name);
        if (!gop.found_existing) {
            gop.value_ptr.* = try std.ArrayList(CallSite).initCapacity(allocator, 4);
        }
        try gop.value_ptr.append(self.allocator, .{ .caller_func = caller_func, .inst = inst });
    }

    pub fn getCallSites(self: *const CallSiteIndex, callee_name: []const u8) ?[]const CallSite {
        if (self.map.get(callee_name)) |sites| {
            return sites.items;
        }
        return null;
    }
};

/// R8.3: Global allocation tracker for cross-function leak detection.
pub const GlobalAllocTracker = struct {
    pub const AllocRecord = struct {
        ptr_id: u32,
        alloc_func: []const u8,
        alloc_func_val: ?c.LLVMValueRef = null,
        alloc_callee: []const u8,
        freed: bool,
        free_func: ?[]const u8,
        is_global_or_static: bool,
        is_conditional: bool = false,
        alloc_size: ?u64 = null,
    };

    allocator: Allocator,
    records_by_ptr: std.AutoHashMap(u64, u32),
    records: std.ArrayList(AllocRecord),

    pub fn init(allocator: Allocator) GlobalAllocTracker {
        return .{
            .allocator = allocator,
            .records_by_ptr = std.AutoHashMap(u64, u32).init(allocator),
            .records = std.ArrayList(AllocRecord).empty,
        };
    }

    pub fn deinit(self: *GlobalAllocTracker) void {
        for (self.records.items) |*rec| {
            self.allocator.free(rec.alloc_func);
            if (rec.alloc_callee.len > 0) self.allocator.free(rec.alloc_callee);
            if (rec.free_func) |f| self.allocator.free(f);
        }
        self.records.deinit(self.allocator);
        self.records_by_ptr.deinit();
    }

    pub fn insertAlloc(self: *GlobalAllocTracker, ptr_val: u64, func_name: []const u8, callee_name: []const u8, is_global: bool, inst_id: u32, is_conditional: bool, func_val: ?c.LLVMValueRef, alloc_size: ?u64) !void {
        const name_owned = try self.allocator.dupe(u8, func_name);
        const callee_owned = if (callee_name.len > 0) try self.allocator.dupe(u8, callee_name) else &[_]u8{};
        const idx = @as(u32, @intCast(self.records.items.len));
        try self.records.append(self.allocator, .{
            .ptr_id = inst_id,
            .alloc_func = name_owned,
            .alloc_func_val = func_val,
            .alloc_callee = callee_owned,
            .freed = false,
            .free_func = null,
            .is_global_or_static = is_global,
            .is_conditional = is_conditional,
            .alloc_size = alloc_size,
        });
        try self.records_by_ptr.put(ptr_val, idx);
    }

    pub fn markFreed(self: *GlobalAllocTracker, ptr_val: u64, func_name: []const u8) bool {
        const idx = self.records_by_ptr.get(ptr_val) orelse return false;
        var rec = &self.records.items[idx];
        if (rec.freed) return true;
        rec.freed = true;
        const free_name_owned = self.allocator.dupe(u8, func_name) catch return true;
        rec.free_func = free_name_owned;
        return true;
    }

    pub fn getLeakCount(self: *const GlobalAllocTracker) u32 {
        return self.leakCount();
    }

    pub fn size(self: *const GlobalAllocTracker) usize {
        return self.records.items.len;
    }

    pub fn leakCount(self: *const GlobalAllocTracker) u32 {
        var count: u32 = 0;
        for (self.records.items) |rec| {
            if (!rec.freed and !rec.is_global_or_static) count += 1;
        }
        return count;
    }

    pub fn getAllocationSize(alloc_inst: c.LLVMValueRef) ?u64 {
        if (@intFromPtr(alloc_inst) == 0) return null;

        const opcode = c.LLVMGetInstructionOpcode(alloc_inst);

        if (opcode == c.LLVMCall or opcode == c.LLVMInvoke) {
            const num_ops = c.LLVMGetNumOperands(alloc_inst);
            if (num_ops < 2) return null;

            const size_op_idx = @as(c_uint, @intCast(num_ops - 2));
            const size_op = c.LLVMGetOperand(alloc_inst, size_op_idx);
            if (@intFromPtr(size_op) == 0) return null;

            if (c.LLVMIsConstant(size_op) != 0) {
                const const_val = c.LLVMConstIntGetZExtValue(size_op);
                return @as(u64, @bitCast(const_val));
            }

            if (num_ops >= 3) {
                const count_op = c.LLVMGetOperand(alloc_inst, @as(c_uint, @intCast(num_ops - 3)));
                if (@intFromPtr(count_op) != 0 and c.LLVMIsConstant(count_op) != 0) {
                    const count_val = c.LLVMConstIntGetZExtValue(count_op);
                    const size_val = c.LLVMConstIntGetZExtValue(size_op);
                    return @as(u64, @bitCast(count_val)) * @as(u64, @bitCast(size_val));
                }
            }
        }

        if (opcode == c.LLVMAlloca) {
            return null;
        }

        return null;
    }
};

/// ANSI color codes for terminal output
pub const Colors = struct {
    const reset = "\x1b[0m";
    const red = "\x1b[31m";
    const yellow = "\x1b[33m";
    const green = "\x1b[32m";
    const blue = "\x1b[34m";
    const magenta = "\x1b[35m";
    const cyan = "\x1b[36m";
    const bold = "\x1b[1m";
    const dim = "\x1b[2m";
};

/// Diagnostic writer for pass output with color support
pub const DiagnosticWriter = struct {
    allocator: Allocator,
    use_color: bool = true,

    pub fn write(self: *DiagnosticWriter, comptime severity: []const u8, comptime format: []const u8, args: anytype) void {
        if (log.current_log_level == .quiet) return;
        if (std.mem.eql(u8, severity, "DEBUG") and log.current_log_level != .debug) return;
        if (std.mem.eql(u8, severity, "INFO") and log.current_log_level == .normal) return;

        const color = comptime getSeverityColor(severity);
        if (self.use_color) {
            log.info(color ++ "[" ++ severity ++ "]" ++ Colors.reset ++ " " ++ format ++ "\n", args);
        } else {
            log.info("[" ++ severity ++ "] " ++ format ++ "\n", args);
        }
    }

    pub fn info(self: *DiagnosticWriter, comptime format: []const u8, args: anytype) void {
        self.write("INFO", format, args);
    }

    pub fn warn(self: *DiagnosticWriter, comptime format: []const u8, args: anytype) void {
        self.write("WARN", format, args);
    }

    pub fn err(self: *DiagnosticWriter, comptime format: []const u8, args: anytype) void {
        self.write("ERROR", format, args);
    }

    pub fn critical(self: *DiagnosticWriter, comptime format: []const u8, args: anytype) void {
        self.write("CRITICAL", format, args);
    }

    pub fn debug(self: *DiagnosticWriter, comptime format: []const u8, args: anytype) void {
        self.write("DEBUG", format, args);
    }
};

fn getSeverityColor(comptime severity: []const u8) []const u8 {
    if (comptime std.mem.eql(u8, severity, "CRITICAL")) {
        return Colors.bold ++ Colors.red;
    } else if (comptime std.mem.eql(u8, severity, "ERROR")) {
        return Colors.red;
    } else if (comptime std.mem.eql(u8, severity, "WARN")) {
        return Colors.yellow;
    } else if (comptime std.mem.eql(u8, severity, "INFO")) {
        return Colors.green;
    } else if (comptime std.mem.eql(u8, severity, "DEBUG")) {
        return Colors.dim;
    }
    return Colors.reset;
}

fn diagToNoiseSeverity(sev: DiagSeverity) NoiseSeverity {
    return switch (sev) {
        .low => .low,
        .medium => .medium,
        .high => .high,
        .critical => .critical,
    };
}