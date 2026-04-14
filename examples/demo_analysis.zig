const std = @import("std");
const OmniScope = @import("OmniScope");
const Pipeline = OmniScope.pipeline.Pipeline;
const PassKind = OmniScope.pass.PassKind;
const PassContext = OmniScope.pass.PassContext;
const DiagnosticWriter = OmniScope.pass.DiagnosticWriter;

const CFGPass = struct {
    pub const name = "cfg";
    pub const kind = PassKind.foundation;
    pub const deps = &[_][]const u8{};
    pub fn run(ctx: *PassContext, diag: *DiagnosticWriter) !void {
        _ = diag;
        if (ctx.module) |mod| {
            var func = llvm.LLVMGetFirstFunction(mod.raw);
            var func_count: u32 = 0;
            while (@intFromPtr(func) != 0) : (func = llvm.LLVMGetNextFunction(func)) {
                const func_name = llvm.LLVMGetValueName(func);
                std.debug.print("  Found function: {s}\n", .{std.mem.span(func_name)});
                func_count += 1;
            }
            try ctx.fact_store.insert(.cfg_edge, 0, func_count, ctx.getNextId());
        }
    }
};

const MemoryAnalysisPass = struct {
    pub const name = "memory-analysis";
    pub const kind = PassKind.analysis;
    pub const deps = &[_][]const u8{"cfg"};
    pub fn run(ctx: *PassContext, diag: *DiagnosticWriter) !void {
        _ = diag;
        if (ctx.module) |mod| {
            var func = llvm.LLVMGetFirstFunction(mod.raw);
            while (@intFromPtr(func) != 0) : (func = llvm.LLVMGetNextFunction(func)) {
                const func_name = std.mem.span(llvm.LLVMGetValueName(func));
                const suspicious = std.mem.eql(u8, func_name, "allocate_array") or
                    std.mem.eql(u8, func_name, "get_name") or
                    std.mem.eql(u8, func_name, "free_twice");
                if (suspicious) {
                    std.debug.print("  [!] Suspicious function: {s}\n", .{func_name});
                }
            }
        }
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== OmniScope Analysis Demo ===\n\n", .{});

    std.debug.print("Loading IR: examples/sample_analysis.bc\n", .{});

    var pipeline = Pipeline.init(allocator);
    defer pipeline.deinit();

    try pipeline.loadIR("examples/sample_analysis.bc");

    std.debug.print("\n--- Registering passes ---\n", .{});
    try pipeline.registerPass(CFGPass);
    try pipeline.registerPass(MemoryAnalysisPass);

    std.debug.print("\n--- Running analysis ---\n", .{});
    const result = try pipeline.runStaticAnalysis();

    std.debug.print("\n--- Analysis Results ---\n", .{});
    std.debug.print("Facts generated: {d}\n", .{result.fact_count});
    std.debug.print("Execution time: {d} ns\n", .{result.execution_time_ns});

    const diagnostics = pipeline.getDiagnosticAggregator().getAll();
    std.debug.print("Diagnostics: {d}\n", .{diagnostics.len});
}

const llvm = OmniScope.ir.llvm_c;
