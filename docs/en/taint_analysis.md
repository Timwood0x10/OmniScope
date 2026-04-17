# Taint Analysis Pass

## Overview

Tracks data flow from tainted sources to sensitive sinks to detect security vulnerabilities.

## Location

```text
src/pass/analysis/taint.zig
```

## TaintPass

```zig
pub const TaintPass = struct {
    pub const name = "taint";
    pub const kind = PassKind.analysis;
    pub const deps = &[_][]const u8{ "cfg", "dfg", "alias" };

    allocator: std.mem.Allocator,
    ctx: *PassContext,
    diag: *DiagnosticWriter,
    store: *FactStore,
    query: QueryEngine,
    taint_graph: TaintGraph,
    func_id: u32,
    sources: std.ArrayList(u32),
    sinks: std.ArrayList(u32),
};
```

### Methods

- **init()** - Initialize pass
- **deinit()** - Clean up resources
- **run(func_id)** - Run analysis on function

## TaintGraph

Manages taint propagation.

```zig
pub const TaintGraph = struct {
    allocator: std.mem.Allocator,
    tainted_nodes: std.AutoHashMap(u32, TaintInfo),
    propagation_edges: std.ArrayList(PropagationEdge),
};
```

### Methods

- **init()** - Initialize graph
- **deinit()** - Clean up
- **markTainted(node_id, source_id)** - Mark node as tainted
- **isTainted(node_id)** - Check if tainted
- **propagate()** - Propagate taint

## Known Sources

- `read`, `getenv`, `fgets`, `scanf`, `recv`, `fread`

### isKnownTaintSourceByName(name)

Check if function is a taint source.

## Known Sinks

- `system`, `printf`, `exec`, `popen`, `sprintf`, `strcpy`

### isKnownTaintSinkByName(name)

Check if function is a taint sink.

## Usage

```zig
var taint_pass = TaintPass.init(allocator, ctx, diag, store, query);
defer taint_pass.deinit();

const result = try taint_pass.run(func_id);
for (result.taint_flows) |flow| {
    std.debug.print("Taint flow: {} -> {}\n", .{ flow.source, flow.sink });
}
```

## Detection

- Command injection
- Format string vulnerabilities
- Buffer overflow
- Path traversal
