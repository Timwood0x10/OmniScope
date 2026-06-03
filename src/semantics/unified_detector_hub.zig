//! Unified Detector Hub — Single-pass Merged Traversal Engine
//!
//! This module implements the core optimization for SemanticResolver:
//! merging 14 independent detector traversals into a single unified pass.

const std = @import("std");
const log = @import("../common/log.zig");
const c = @import("../ir/llvm_raw.zig").c;
const llvm_safe = @import("../ir/llvm_safe.zig");

const DetectorInterface = @import("./detector_interface.zig").DetectorInterface;
const DetectorContext = @import("./detector_interface.zig").DetectorContext;
const DetectorStats = @import("./detector_interface.zig").DetectorStats;
const DiagnosticWriter = @import("../pass/pass.zig").DiagnosticWriter;
const SemanticTree = @import("./semantic_tree.zig").SemanticTree;
const FunctionIR = @import("../ir/ir_store.zig").FunctionIR;
const ModuleIRStore = @import("../ir/ir_store.zig").ModuleIRStore;

/// Unified Detector Hub — orchestrates all semantic detectors in a single pass.
pub const UnifiedDetectorHub = struct {
    detectors: struct {
        ch04: DetectorInterface,
        ch05: DetectorInterface,
        ch06: DetectorInterface,
        ch08: DetectorInterface,
        _ch09_reserved: DetectorInterface,
        ch10: DetectorInterface,
        posix: DetectorInterface,
        param_attr: DetectorInterface,
        heap_provenance: DetectorInterface,
        interior_mut: DetectorInterface,
        into_raw: DetectorInterface,
        library_alloc: DetectorInterface,
        lang_detector: DetectorInterface,
        resolution_engine: DetectorInterface,
    },

    stats: struct {
        ch04: DetectorStats,
        ch05: DetectorStats,
        ch06: DetectorStats,
        ch08: DetectorStats,
        ch09: DetectorStats,
        ch10: DetectorStats,
        posix: DetectorStats,
        param_attr: DetectorStats,
        heap_provenance: DetectorStats,
        interior_mut: DetectorStats,
        into_raw: DetectorStats,
        library_alloc: DetectorStats,
        lang_detector: DetectorStats,
        resolution_engine: DetectorStats,
    },

    ctx: ?DetectorContext,

    total_instructions_processed: u64 = 0,

    pub fn init(
        module: c.LLVMModuleRef,
        ir_store: *ModuleIRStore,
        srt: *SemanticTree,
        diag: *DiagnosticWriter,
        allocator: std.mem.Allocator,
    ) UnifiedDetectorHub {
        _ = module;
        _ = ir_store;
        _ = srt;
        _ = diag;
        _ = allocator;

        return .{
            .detectors = .{
                .ch04 = .{},
                .ch05 = .{},
                .ch06 = .{},
                .ch08 = .{},
                ._ch09_reserved = .{},
                .ch10 = .{},
                .posix = .{},
                .param_attr = .{},
                .heap_provenance = .{},
                .interior_mut = .{},
                .into_raw = .{},
                .library_alloc = .{},
                .lang_detector = .{},
                .resolution_engine = .{},
            },
            .stats = .{
                .ch04 = .{},
                .ch05 = .{},
                .ch06 = .{},
                .ch08 = .{},
                .ch09 = .{},
                .ch10 = .{},
                .posix = .{},
                .param_attr = .{},
                .heap_provenance = .{},
                .interior_mut = .{},
                .into_raw = .{},
                .library_alloc = .{},
                .lang_detector = .{},
                .resolution_engine = .{},
            },
            .ctx = null,
            .total_instructions_processed = 0,
        };
    }

    pub fn registerDetector(self: *UnifiedDetectorHub, name: []const u8, interface: DetectorInterface) void {
        if (std.mem.eql(u8, name, "ch04")) {
            self.detectors.ch04 = interface;
        } else if (std.mem.eql(u8, name, "ch05")) {
            self.detectors.ch05 = interface;
        } else if (std.mem.eql(u8, name, "ch06")) {
            self.detectors.ch06 = interface;
        } else if (std.mem.eql(u8, name, "ch08")) {
            self.detectors.ch08 = interface;
        } else if (std.mem.eql(u8, name, "ch09")) {
            self.detectors._ch09_reserved = interface;
        } else if (std.mem.eql(u8, name, "ch10")) {
            self.detectors.ch10 = interface;
        } else if (std.mem.eql(u8, name, "posix")) {
            self.detectors.posix = interface;
        } else if (std.mem.eql(u8, name, "param_attr")) {
            self.detectors.param_attr = interface;
        } else if (std.mem.eql(u8, name, "heap_provenance")) {
            self.detectors.heap_provenance = interface;
        } else if (std.mem.eql(u8, name, "interior_mut")) {
            self.detectors.interior_mut = interface;
        } else if (std.mem.eql(u8, name, "into_raw")) {
            self.detectors.into_raw = interface;
        } else if (std.mem.eql(u8, name, "library_alloc")) {
            self.detectors.library_alloc = interface;
        } else if (std.mem.eql(u8, name, "lang_detector")) {
            self.detectors.lang_detector = interface;
        } else if (std.mem.eql(u8, name, "resolution_engine")) {
            self.detectors.resolution_engine = interface;
        }
    }

    pub fn processInstruction(self: *UnifiedDetectorHub, inst: c.LLVMValueRef, opcode: c_uint) void {
        const ctx = &self.ctx.?;
        self.total_instructions_processed += 1;

        switch (opcode) {
            c.LLVMCall, c.LLVMInvoke => {
                const callee_name = ctx.fir.getCalleeNameByInst(inst);
                self.dispatchCall(ctx, inst, callee_name);
            },
            c.LLVMBitCast => self.dispatchBitcast(ctx, inst),
            c.LLVMLoad => self.dispatchLoad(ctx, inst),
            c.LLVMStore => self.dispatchStore(ctx, inst),
            c.LLVMAlloca => self.dispatchAlloca(ctx, inst),
            c.LLVMGetElementPtr => self.dispatchGEP(ctx, inst),
            c.LLVMRet => self.dispatchRet(ctx, inst),
            c.LLVMPtrToInt, c.LLVMIntToPtr => self.dispatchPtrIntConversion(ctx, inst),
            c.LLVMPHI => self.dispatchPHI(ctx, inst),
            else => {},
        }
    }

    pub fn onFunctionEnter(self: *UnifiedDetectorHub, module: c.LLVMModuleRef, func: c.LLVMValueRef, fir: *FunctionIR, srt: anytype, diag: *DiagnosticWriter, allocator: std.mem.Allocator) void {
        self.ctx = DetectorContext.init(module, func, fir, self.ctx.?.ir_store, srt, diag, allocator);
        self.dispatchFunctionEnter();
    }

    pub fn onFunctionExit(self: *UnifiedDetectorHub) void {
        _ = self;
    }

    pub fn getStats(self: *const UnifiedDetectorHub) HubStats {
        return .{
            .total_instructions = self.total_instructions_processed,
            .detector_calls = .{
                self.stats.ch04.total_calls,
                self.stats.ch05.total_calls,
                self.stats.ch06.total_calls,
                self.stats.ch08.total_calls,
                self.stats.ch09.total_calls,
                self.stats.ch10.total_calls,
                self.stats.posix.total_calls,
                self.stats.param_attr.total_calls,
                self.stats.heap_provenance.total_calls,
                self.stats.interior_mut.total_calls,
                self.stats.into_raw.total_calls,
                self.stats.library_alloc.total_calls,
                self.stats.lang_detector.total_calls,
                self.stats.resolution_engine.total_calls,
            },
            .total_errors = blk: {
                var sum: u64 = 0;
                inline for (std.meta.fields(@TypeOf(self.stats))) |field| {
                    sum += @field(self.stats, field.name).error_count;
                }
                break :blk sum;
            },
            .total_resolutions = blk: {
                var sum: u64 = 0;
                inline for (std.meta.fields(@TypeOf(self.stats))) |field| {
                    sum += @field(self.stats, field.name).resolutions_made;
                }
                break :blk sum;
            },
        };
    }

    fn dispatchCall(self: *UnifiedDetectorHub, ctx: *DetectorContext, inst: c.LLVMValueRef, callee_name: ?[]const u8) void {
        const detectors_list = [_]struct { iface: *DetectorInterface, stats: *DetectorStats }{
            .{ .iface = &self.detectors.ch04, .stats = &self.stats.ch04 },
            .{ .iface = &self.detectors.ch05, .stats = &self.stats.ch05 },
            .{ .iface = &self.detectors.ch06, .stats = &self.stats.ch06 },
            .{ .iface = &self.detectors.ch08, .stats = &self.stats.ch08 },
            .{ .iface = &self.detectors.ch10, .stats = &self.stats.ch10 },
            .{ .iface = &self.detectors.posix, .stats = &self.stats.posix },
            .{ .iface = &self.detectors.heap_provenance, .stats = &self.stats.heap_provenance },
            .{ .iface = &self.detectors.interior_mut, .stats = &self.stats.interior_mut },
            .{ .iface = &self.detectors.into_raw, .stats = &self.stats.into_raw },
            .{ .iface = &self.detectors.library_alloc, .stats = &self.stats.library_alloc },
            .{ .iface = &self.detectors.resolution_engine, .stats = &self.stats.resolution_engine },
        };

        for (detectors_list) |entry| {
            if (entry.iface.instruction.onCall) |handler| {
                entry.stats.total_calls += 1;
                handler(ctx, inst, callee_name) catch |err| {
                    entry.stats.error_count += 1;
                    log.warn("[UnifiedHub] call handler error: {any}", .{err});
                };
            }
        }
    }

    fn dispatchBitcast(self: *UnifiedDetectorHub, ctx: *DetectorContext, inst: c.LLVMValueRef) void {
        const detectors_list = [_]struct { iface: *DetectorInterface, stats: *DetectorStats }{
            .{ .iface = &self.detectors.ch04, .stats = &self.stats.ch04 },
            .{ .iface = &self.detectors.heap_provenance, .stats = &self.stats.heap_provenance },
        };

        for (detectors_list) |entry| {
            if (entry.iface.instruction.onBitcast) |handler| {
                entry.stats.total_calls += 1;
                handler(ctx, inst) catch |err| {
                    entry.stats.error_count += 1;
                    log.warn("[UnifiedHub] bitcast handler error: {any}", .{err});
                };
            }
        }
    }

    fn dispatchLoad(self: *UnifiedDetectorHub, ctx: *DetectorContext, inst: c.LLVMValueRef) void {
        const detectors_list = [_]struct { iface: *DetectorInterface, stats: *DetectorStats }{
            .{ .iface = &self.detectors.ch05, .stats = &self.stats.ch05 },
            .{ .iface = &self.detectors.heap_provenance, .stats = &self.stats.heap_provenance },
        };

        for (detectors_list) |entry| {
            if (entry.iface.instruction.onLoad) |handler| {
                entry.stats.total_calls += 1;
                handler(ctx, inst) catch |err| {
                    entry.stats.error_count += 1;
                    log.warn("[UnifiedHub] load handler error: {any}", .{err});
                };
            }
        }
    }

    fn dispatchStore(self: *UnifiedDetectorHub, ctx: *DetectorContext, inst: c.LLVMValueRef) void {
        if (self.detectors.ch06.instruction.onStore) |handler| {
            self.stats.ch06.total_calls += 1;
            handler(ctx, inst) catch |err| {
                self.stats.ch06.error_count += 1;
                log.warn("[UnifiedHub] store handler error: {any}", .{err});
            };
        }
    }

    fn dispatchAlloca(self: *UnifiedDetectorHub, ctx: *DetectorContext, inst: c.LLVMValueRef) void {
        if (self.detectors.heap_provenance.instruction.onAlloca) |handler| {
            self.stats.heap_provenance.total_calls += 1;
            handler(ctx, inst) catch |err| {
                self.stats.heap_provenance.error_count += 1;
                log.warn("[UnifiedHub] alloca handler error: {any}", .{err});
            };
        }
    }

    fn dispatchGEP(self: *UnifiedDetectorHub, ctx: *DetectorContext, inst: c.LLVMValueRef) void {
        if (self.detectors.heap_provenance.instruction.onGEP) |handler| {
            self.stats.heap_provenance.total_calls += 1;
            handler(ctx, inst) catch |err| {
                self.stats.heap_provenance.error_count += 1;
                log.warn("[UnifiedHub] GEP handler error: {any}", .{err});
            };
        }
    }

    fn dispatchRet(self: *UnifiedDetectorHub, ctx: *DetectorContext, inst: c.LLVMValueRef) void {
        if (self.detectors.ch06.instruction.onRet) |handler| {
            self.stats.ch06.total_calls += 1;
            handler(ctx, inst) catch |err| {
                self.stats.ch06.error_count += 1;
                log.warn("[UnifiedHub] ret handler error: {any}", .{err});
            };
        }
    }

    fn dispatchPtrIntConversion(self: *UnifiedDetectorHub, ctx: *DetectorContext, inst: c.LLVMValueRef) void {
        if (self.detectors.ch04.instruction.onPtrIntConversion) |handler| {
            self.stats.ch04.total_calls += 1;
            handler(ctx, inst) catch |err| {
                self.stats.ch04.error_count += 1;
                log.warn("[UnifiedHub] ptr/int handler error: {any}", .{err});
            };
        }
    }

    fn dispatchPHI(self: *UnifiedDetectorHub, ctx: *DetectorContext, inst: c.LLVMValueRef) void {
        if (self.detectors.heap_provenance.instruction.onPHI) |handler| {
            self.stats.heap_provenance.total_calls += 1;
            handler(ctx, inst) catch |err| {
                self.stats.heap_provenance.error_count += 1;
                log.warn("[UnifiedHub] PHI handler error: {any}", .{err});
            };
        }
    }

    fn dispatchFunctionEnter(self: *UnifiedDetectorHub) void {
        const ctx = &self.ctx.?;
        if (self.detectors.param_attr.function.onFunctionEnter) |handler| {
            self.stats.param_attr.total_calls += 1;
            handler(ctx) catch |err| {
                self.stats.param_attr.error_count += 1;
                log.warn("[UnifiedHub] function enter handler error: {any}", .{err});
            };
        }
    }
};

pub const HubStats = struct {
    total_instructions: u64,
    detector_calls: [14]u64,
    total_errors: u64,
    total_resolutions: u64,

    pub fn format(self: *const HubStats, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.writeAll(
            \\UnifiedDetectorHub Statistics:
            \\  Total Instructions Processed: {}
            \\  Per-Detector Calls:
            \\
        , .{self.total_instructions});

        const names = [14][]const u8{
            "ch04",      "ch05",      "ch06",      "ch08",
            "ch09",      "ch10",      "posix",     "param_attr",
            "heap_prov", "int_mut",   "into_raw",  "lib_alloc",
            "lang_det",  "res_eng",
        };

        for (self.detector_calls, 0..) |count, i| {
            try writer.print("    {:12} : {} calls\n", .{ names[i], count });
        }

        try writer.print(
            \\  Total Errors: {}
            \\  Total Resolutions: {}
            \\
        , .{ self.total_errors, self.total_resolutions });
    }
};
