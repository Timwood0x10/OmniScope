const std = @import("std");
const OmniScope = @import("OmniScope");
const Pipeline = OmniScope.pipeline.Pipeline;
const call_graph = OmniScope.cross_lang;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            OmniScope.log.warn("main", "Memory leak detected!\n", .{});
        }
    }

    const allocator = gpa.allocator();

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    _ = args.next();

    var input_path: ?[]const u8 = null;
    var show_help = false;

    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            show_help = true;
        } else if (std.mem.eql(u8, arg, "-v") or std.mem.eql(u8, arg, "--verbose") or std.mem.eql(u8, arg, "-d") or std.mem.eql(u8, arg, "--debug")) {
            // Ignored for now
        } else if (std.mem.eql(u8, arg, "--version")) {
            std.debug.print("OmniScope v1.0.0\n", .{});
            return;
        } else if (arg[0] == '-') {
            std.debug.print("Unknown option: {s}\n", .{arg});
            show_help = true;
        } else {
            input_path = arg;
        }
    }

    if (show_help) {
        std.debug.print("OmniScope - Universal LLVM Analysis Framework\n" ++
            "\n" ++
            "Usage: omniscope [options] <input.bc>\n" ++
            "\n" ++
            "Options:\n" ++
            "  -h, --help          Show this help message\n" ++
            "  -v, --verbose       Enable verbose logging\n" ++
            "  -d, --debug         Enable debug logging\n" ++
            "  --version           Show version information\n" ++
            "\n" ++
            "Analysis Types:\n" ++
            "  Cross-Language Data Flow (default)\n" ++
            "  Detects: Source -> Sink paths across FFI boundaries\n" ++
            "\n", .{});
        return;
    }

    const path = input_path orelse {
        std.debug.print("Error: No input file specified\n", .{});
        return;
    };

    std.debug.print("=== OmniScope Cross-Language Data Flow Analysis ===\n\n", .{});

    var pipeline = Pipeline.init(allocator);
    defer pipeline.deinit();

    std.debug.print("[*] Loading IR: {s}\n", .{path});
    pipeline.loadIR(path) catch |err| {
        std.debug.print("[!] Failed to load IR: {}\n", .{err});
        return err;
    };

    if (pipeline.getIRLoader()) |l| {
        std.debug.print("[*] IR loaded: {d} functions\n\n", .{l.getFunctionCount()});
    }

    std.debug.print("[*] Registering analysis passes...\n", .{});
    try pipeline.registerPass(call_graph.CallGraphPass);

    std.debug.print("[*] Running analysis...\n\n", .{});
    _ = pipeline.runStaticAnalysis() catch |err| {
        std.debug.print("[!] Analysis failed: {}\n", .{err});
        return err;
    };

    std.debug.print("\n=== Analysis Results ===\n", .{});
    const diagnostics = pipeline.getDiagnosticAggregator().getAll();

    if (diagnostics.len == 0) {
        std.debug.print("No issues found.\n", .{});
    } else {
        for (diagnostics) |diag| {
            std.debug.print("[{s}] {s}\n", .{
                @tagName(diag.severity),
                diag.message,
            });
        }
    }
}
