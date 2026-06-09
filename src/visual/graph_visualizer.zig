//! Graph Visualizer - Generate interactive HTML/SVG visualizations.
//!
//! Produces standalone HTML files (no HTTP server needed) that visualize:
//!
//!   1. **Memory Graph**: Allocation nodes with alias chains, free status, and double-free detection.
//!      Nodes are colored by status:
//!        - Green: Active allocation (not freed)
//!        - Red: Freed allocation
//!        - Orange: Double-free detected
//!        - Gray: Unknown origin
//!
//!   2. **Call Graph**: Function call relationships with FFI boundary highlighting.
//!      Edges show caller→callee direction.
//!      FFI boundary nodes are highlighted in yellow/orange.
//!
//! Output files are self-contained HTML with embedded SVG, CSS, and JavaScript.
//! Open directly in any modern browser (Chrome, Firefox, Safari, Edge).
//!
//! Usage:
//!   ```zig
//!   var viz = try GraphVisualizer.init(allocator);
//!   defer viz.deinit();
//!
//!   // Export issues as JSON
//!   try viz.exportIssuesJson(&issues, "omniscope_issues.json");
//!
//!   // Export from pre-built JSON string
//!   try viz.exportFromJson(json_str, "omniscope_report.html");
//!
//!   // Export issues as interactive HTML
//!   try viz.exportIssuesHtml(&issues, "omniscope_report.html");
//!   ```

const std = @import("std");

const log = std.log.scoped(.graph_visualizer);

/// Lightweight issue snapshot for visualization.
/// Defined locally to avoid cross-module dependency on diag/issue.zig.
pub const GraphIssue = struct {
    kind: GraphKind,
    message: []const u8,
    function: []const u8,
    severity: []const u8,
    confidence: f32,
    line: u32,
};

pub const GraphKind = enum {
    memory_leak,
    use_after_free,
    double_free,
    cross_language_leak,
    cross_language_free,
    malloc_unchecked,
    null_dereference,
    invalid_free,
    write_to_immutable,
    borrow_escape,
    ffi_unsafe_call,
    unchecked_return,
    type_mismatch,
    command_injection,
    buffer_overflow,
    format_string,
    callback_signature_mismatch,
    static_buffer_misuse,
    other,
};

/// Main visualizer struct.
pub const GraphVisualizer = struct {
    allocator: std.mem.Allocator,
    /// Buffered output for the HTML file.
    buf: std.ArrayList(u8),

    pub fn init(allocator: std.mem.Allocator) !GraphVisualizer {
        const self = GraphVisualizer{
            .allocator = allocator,
            .buf = std.ArrayList(u8).initCapacity(allocator, 0) catch return error.OutOfMemory,
        };
        return self;
    }

    pub fn deinit(self: *GraphVisualizer) void {
        self.buf.deinit(self.allocator);
    }

    /// Generate a memory-graph JSON from issues (dynamic, no mock data).
    ///
    /// Generate a structured JSON from issues for meaningful visualization.
    ///
    /// Output: { meta{total_issues, function_count}, functions[{name, count, issues[]}],
    ///          summary{by_kind{}, by_severity{}} }
    pub fn exportIssuesJson(
        self: *GraphVisualizer,
        issues: []const GraphIssue,
        output_path: []const u8,
    ) !void {
        var buf = std.ArrayList(u8).initCapacity(self.allocator, 4096) catch return error.OutOfMemory;
        defer buf.deinit(self.allocator);
        const writer = buf.writer(self.allocator);

        var func_map = std.StringHashMap(std.ArrayList(GraphIssue)).init(self.allocator);
        defer {
            var iter = func_map.iterator();
            while (iter.next()) |entry| entry.value_ptr.deinit(self.allocator);
            func_map.deinit();
        }

        var mem_count: usize = 0;
        for (issues) |issue| {
            if (!isMemoryKind(issue.kind)) continue;
            mem_count += 1;
            const gop = try func_map.getOrPut(issue.function);
            if (!gop.found_existing) {
                gop.value_ptr.* = std.ArrayList(GraphIssue).initCapacity(self.allocator, 4) catch return error.OutOfMemory;
            }
            try gop.value_ptr.append(self.allocator, issue);
        }

        var func_list = std.ArrayList(struct { name: []const u8, issues: []GraphIssue }).initCapacity(self.allocator, 0) catch return error.OutOfMemory;
        defer {
            for (func_list.items) |entry| {
                self.allocator.free(entry.issues);
            }
            func_list.deinit(self.allocator);
        }

        var fiter = func_map.iterator();
        while (fiter.next()) |entry| {
            // Deep copy issues slice to avoid dangling reference after func_map deinit.
            const issues_copy = try self.allocator.alloc(GraphIssue, entry.value_ptr.items.len);
            errdefer self.allocator.free(issues_copy);
            @memcpy(issues_copy, entry.value_ptr.items);
            try func_list.append(self.allocator, .{ .name = entry.key_ptr.*, .issues = issues_copy });
        }

        const FuncEntry = @TypeOf(func_list.items[0]);
        std.sort.block(
            FuncEntry,
            func_list.items,
            {},
            struct {
                fn lessThan(_: void, a: FuncEntry, b: FuncEntry) bool {
                    return a.issues.len > b.issues.len;
                }
            }.lessThan,
        );

        var kind_counts = std.StringHashMap(usize).init(self.allocator);
        defer kind_counts.deinit();
        for (issues) |issue| {
            if (!isMemoryKind(issue.kind)) continue;
            const ks = @tagName(issue.kind);
            if (kind_counts.get(ks)) |v| {
                kind_counts.put(ks, v + 1) catch {};
            } else {
                kind_counts.put(ks, 1) catch {};
            }
        }

        try writer.writeAll("{\"meta\":{\"total_issues\":");
        try writer.print("{d}", .{mem_count});
        try writer.writeAll(",\"function_count\":");
        try writer.print("{d}", .{func_list.items.len});
        try writer.writeAll("},\"functions\":[");

        var first_func = true;
        for (func_list.items) |entry| {
            if (!first_func) try writer.writeAll(",");
            first_func = false;

            try writer.writeAll("{\"name\":\"");
            try writeJsonString(&writer, entry.name);
            try writer.writeAll("\",\"count\":");
            try writer.print("{d}", .{entry.issues.len});
            try writer.writeAll(",\"issues\":[");

            var first_issue = true;
            for (entry.issues) |issue| {
                if (!first_issue) try writer.writeAll(",");
                first_issue = false;

                try writer.writeAll("{\"kind\":\"");
                try writeJsonString(&writer, @tagName(issue.kind));
                try writer.writeAll("\",\"severity\":\"");
                try writeJsonString(&writer, issue.severity);
                try writer.writeAll("\",\"line\":");
                try writer.print("{d}", .{issue.line});
                try writer.writeAll(",\"confidence\":");
                try writer.print("{d}", .{@as(u32, @intFromFloat(issue.confidence * 100))});
                try writer.writeAll(",\"msg\":\"");
                try writeJsonString(&writer, issue.message);
                try writer.writeAll("\"}");
            }

            try writer.writeAll("]}");
        }

        try writer.writeAll("],\"summary\":{\"by_kind\":{");

        var first_kc = true;
        const kinds_ordered = [_][]const u8{
            "double_free",        "use_after_free",      "borrow_escape",
            "memory_leak",        "malloc_unchecked",    "invalid_free",
            "write_to_immutable", "cross_language_leak", "null_dereference",
        };
        for (kinds_ordered) |ks| {
            if (kind_counts.get(ks)) |cnt| {
                if (!first_kc) try writer.writeAll(",");
                first_kc = false;
                try writer.writeAll("\"");
                try writeJsonString(&writer, ks);
                try writer.writeAll("\":");
                try writer.print("{d}", .{cnt});
            }
        }

        try writer.writeAll("}}}");

        const file = try std.fs.cwd().createFile(output_path, .{});
        defer file.close();
        try file.writeAll(buf.items);
    }

    /// Render an HTML memory-graph from a previously-generated JSON file.
    pub fn exportFromJson(
        self: *GraphVisualizer,
        json_path: []const u8,
        html_path: []const u8,
    ) !void {
        const max_json_size: usize = 100 * 1024 * 1024; // 100MB
        const json_data = std.fs.cwd().readFileAlloc(self.allocator, json_path, max_json_size) catch |err| {
            log.warn("Failed to read JSON file '{s}': {}", .{ json_path, err });
            return error.JsonReadFailed;
        };
        defer self.allocator.free(json_data);

        self.buf.items.len = 0;
        const writer = self.buf.writer(self.allocator);

        try writer.writeAll(HTML_HEADER);
        try writer.writeAll(MEMORY_CSS);
        try writer.writeAll(HTML_BODY_OPEN);

        // Embed the JSON data as a JS constant.
        // Sanitize: escape </script> sequences to prevent XSS via JSON content.
        try writer.writeAll("const _graphData = ");
        for (json_data) |ch| {
            if (ch == '<') {
                try writer.writeAll("\\u003c");
            } else if (ch == '>') {
                try writer.writeAll("\\u003e");
            } else if (ch == '&') {
                try writer.writeAll("\\u0026");
            } else {
                const buf = [_]u8{ch};
                try writer.writeAll(&buf);
            }
        }
        try writer.writeAll(";\n");

        try writer.writeAll(MEMORY_JS);
        try writer.writeAll(HTML_FOOTER);

        // Write HTML file
        const file = try std.fs.cwd().createFile(html_path, .{});
        defer file.close();
        try file.writeAll(self.buf.items);
    }

    /// One-shot convenience: generate JSON + render HTML in one call.
    pub fn exportIssuesHtml(
        self: *GraphVisualizer,
        issues: []const GraphIssue,
        json_path: []const u8,
        html_path: []const u8,
    ) !void {
        try self.exportIssuesJson(issues, json_path);
        try self.exportFromJson(json_path, html_path);
    }
};

// ═══════════════════════════════════════════════════════════════
// Helper functions for issue-to-graph mapping
// ═══════════════════════════════════════════════════════════════

fn isMemoryKind(kind: GraphKind) bool {
    return switch (kind) {
        .memory_leak,
        .use_after_free,
        .double_free,
        .cross_language_leak,
        .cross_language_free,
        .malloc_unchecked,
        .null_dereference,
        .invalid_free,
        .borrow_escape,
        => true,
        else => false,
    };
}

fn kindToColor(kind: GraphKind) []const u8 {
    return switch (kind) {
        .memory_leak, .cross_language_leak, .cross_language_free => "#f39c12",
        .use_after_free, .borrow_escape => "#e94560",
        .double_free => "#e74c3c",
        .malloc_unchecked, .null_dereference => "#9b59b6",
        .invalid_free => "#e67e22",
        .ffi_unsafe_call => "#c0392b",
        .unchecked_return => "#8e44ad",
        .type_mismatch => "#d35400",
        .command_injection => "#c0392b",
        .buffer_overflow => "#e74c3c",
        .format_string => "#e67e22",
        .callback_signature_mismatch => "#f39c12",
        .static_buffer_misuse => "#2980b9",
        .other => "#666",
    };
}

fn kindToStatus(kind: GraphKind) []const u8 {
    return switch (kind) {
        .memory_leak, .cross_language_leak, .malloc_unchecked, .null_dereference => "active",
        .use_after_free, .borrow_escape, .invalid_free => "freed",
        .double_free => "doublefree",
        .ffi_unsafe_call, .command_injection, .buffer_overflow => "critical",
        .static_buffer_misuse => "warning",
        .other => "unknown",
    };
}

/// Write a JSON-escaped string to the writer.
///
/// Escapes: " → \", \ → \\, newline → \n, tab → \t, carriage return → \r,
/// and all other control characters (< 0x20) → \uXXXX.
fn writeJsonString(writer: anytype, s: []const u8) !void {
    for (s) |ch| {
        switch (ch) {
            '"' => try writer.writeAll("\\\""),
            '\\' => try writer.writeAll("\\\\"),
            '\n' => try writer.writeAll("\\n"),
            '\t' => try writer.writeAll("\\t"),
            '\r' => try writer.writeAll("\\r"),
            else => {
                if (ch < 0x20) {
                    const hex = "0123456789abcdef";
                    const hi = hex[ch >> 4];
                    const lo = ch & 0x0f;
                    try writer.writeAll("\\u00");
                    const hibuf = [_]u8{hi};
                    const lobuf = [_]u8{hex[lo]};
                    try writer.writeAll(&hibuf);
                    try writer.writeAll(&lobuf);
                } else {
                    const buf = [_]u8{ch};
                    try writer.writeAll(&buf);
                }
            },
        }
    }
}

// ═══════════════════════════════════════════════════════════════
// HTML template fragments
// ═══════════════════════════════════════════════════════════════

const HTML_HEADER =
    "<!DOCTYPE html>\n" ++
    "<html lang=\"en\">\n" ++
    "<head>\n" ++
    "<meta charset=\"UTF-8\">\n" ++
    "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">\n" ++
    "<title>OmniScope Memory Graph</title>\n" ++
    " <style>\n\n";

const HTML_BODY_OPEN =
    " </style>\n" ++
    " </head>\n" ++
    " <body>\n" ++
    " <div id=toolbar>\n" ++
    "   <h2>🧠 OmniScope Memory Graph</h2>\n" ++
    "   <input type=text id=search placeholder=\"Search functions...\" oninput=\"filterFunctions()\">\n" ++
    "   <span id=stats></span>\n" ++
    " </div>\n" ++
    " <div id=summary-panel></div>\n" ++
    " <div id=main-layout style=\"display:flex;gap:0;height:calc(100vh - 130px)\">\n" ++
    " <div id=func-tree style=\"width:260px;min-width:200px;overflow-y:auto;background:#161b22;border-right:1px solid #30363d;padding:8px 0\"></div>\n" ++
    " <div id=graph-wrap style=\"flex:1;position:relative;overflow:hidden\">\n" ++
    " <svg id=graph width=\"100%\" height=\"100%\" style=\"cursor:grab;display:block;background:#0d1117\"></svg>\n" ++
    " </div>\n" ++
    " <div id=detail-panel style=\"width:320px;min-width:280px;overflow-y:auto;background:#161b22;border-left:1px solid #30363d;padding:16px\"></div>\n" ++
    " </div>\n" ++
    " <div id=tooltip style=\"display:none;position:absolute;background:#222;color:#fff;padding:6px 10px;border-radius:6px;font-size:12px;max-width:360px;z-index:1000;box-shadow:0 2px 16px rgba(0,0,0,0.5);pointer-events:none;line-height:1.4\"></div>\n" ++
    " <script>\n\n";

const HTML_FOOTER =
    " </script>\n" ++
    " </body>\n" ++
    " </html>\n\n";

// ═══════════════════════════════════════════════════════════════
// Embedded CSS for Memory Graph
// ═══════════════════════════════════════════════════════════════

const MEMORY_CSS =
    \\* { margin:0; padding:0; box-sizing:border-box; font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif; }
    \\body { background:#0d1117; color:#e0e0e0; overflow:hidden; }
    \\#toolbar { padding:10px 20px; background:#161b22; display:flex; align-items:center; gap:15px; flex-wrap:wrap; border-bottom:1px solid #30363d; }
    \\#toolbar h2 { color:#f85149; font-size:18px; margin-right:auto; }
    \\#toolbar input[type=text] { padding:6px 12px; border:1px solid #30363d; border-radius:6px; background:#0d1117; color:#e0e0e0; width:220px; outline:none; }
    \\#toolbar input[type=text]:focus { border-color:#58a6ff; }
    \\#toolbar #stats { color:#58a6ff; font-size:13px; font-weight:bold; }
    \\#summary-panel { padding:8px 20px; background:#161b22; border-bottom:1px solid #30363d; }
    \\#func-tree { scrollbar-width:thin; scrollbar-color:#30363d transparent; }
    \\.func-item { display:flex; align-items:center; gap:8px; padding:6px 16px; cursor:pointer; transition:background 0.15s; border-left:3px solid transparent; }
    \\.func-item:hover { background:#1c2128; }
    \\.func-item.selected { background:#1f2937; border-left-color:#58a6ff; }
    \\.func-badge { min-width:24px;height:24px;border-radius:12px;display:flex;align-items:center;justify-content:center;font-size:11px;font-weight:bold;color:#fff;flex-shrink:0; }
    \\.func-name { flex:1;font-size:13px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap; }
    \\.func-icons { font-size:12px;flex-shrink:0;opacity:0.8; }
    \\#detail-panel { scrollbar-width:thin; scrollbar-color:#30363d transparent; }
    \\.lifecycle { margin-top:8px; }
    \\.lifecycle-group { margin-bottom:12px; background:#161b22; border-radius:8px; overflow:hidden; border:1px solid #21262d; }
    \\.lifecycle-header { padding:8px 14px; font-size:13px; display:flex;align-items:center;gap:6px; background:#1c2128; }
    \\.lifecycle-item { display:flex;align-items:center;gap:8px;padding:5px 14px 5px 18px;border-top:1px solid #21262d;cursor:pointer;transition:background 0.15s;font-size:12px;line-height:1.4; }
    \\.lifecycle-item:hover { background:#1c2128; }
    \\.sev-dot { width:8px;height:8px;border-radius:50%;flex-shrink:0; }
    \\.line-num { color:#888;font-size:11px;min-width:32px;flex-shrink:0;font-family:monospace; }
    \\.issue-msg { flex:1;color:#ccc;overflow:hidden;text-overflow:ellipsis;white-space:nowrap; }
    \\.conf { color:#888;font-size:11px;min-width:36px;text-align:right;flex-shrink:0;font-family:monospace; }
    \\
;

// ═══════════════════════════════════════════════════════════════
// Embedded JavaScript for Memory Graph interactivity
// ═══════════════════════════════════════════════════════════════

const MEMORY_JS =
    \\let D = _graphData || {meta:{total_issues:0,function_count:0},functions:[],summary:{by_kind:{}}};
    \\let svg, g;
    \\let nodes = [], edges = [];
    \\let transform = {x:0, y:0, k:1};
    \\let dragging = false, lastPos = null, dragNode = null;
    \\const KIND = {
    \\  double_free:{c:'#e74c3c',icon:'💥'}, use_after_free:{c:'#e94560',icon:'⚠️'},
    \\  borrow_escape:{c:'#e94560',icon:'🏃'}, memory_leak:{c:'#f39c12',icon:'🔴'},
    \\  malloc_unchecked:{c:'#9b59b6',icon:'🟣'}, invalid_free:{c:'#e67e22',icon:'🔶'},
    \\  cross_language_leak:{c:'#f39c12',icon:'🔴'}, null_dereference:{c:'#9b59b6',icon:'🟣'},
    \\};
    \\const SEV = {critical:'#e74c3c',high:'#e94560',medium:'#f39c12',low:'#888'};
    \\
    \\function init() {
    \\  svg = document.getElementById('graph');
    \\  g = document.createElementNS('http://www.w3.org/2000/svg','g');
    \\  svg.appendChild(g);
    \\  buildGraph();
    \\  runForceLayout();
    \\  renderGraph();
    \\  renderSidebar();
    \\  renderSummary();
    \\  window.addEventListener('resize', fitView);
    \\  svg.addEventListener('wheel', onWheel,{passive:false});
    \\  svg.addEventListener('mousedown', onMouseDown);
    \\  svg.addEventListener('mousemove', onMouseMove);
    \\  svg.addEventListener('mouseup', onMouseUp);
    \\  svg.addEventListener('mouseleave', onMouseUp);
    \\}
    \\
    \\function buildGraph() {
    \\  nodes = [];
    \\  edges = [];
    \\  const N = D.functions.length;
    \\  if (N === 0) return;
    \\  const maxCnt = Math.max(...D.functions.map(f=>f.count),1);
    \\  for (let i = 0; i < N; i++) {
    \\    const fn = D.functions[i];
    \\    const worstSev = fn.issues.reduce((a,b)=>sevOrder(a.severity)<sevOrder(b.severity)?a:b,{severity:'low'});
    \\    const kinds = {}; for (const iss of fn.issues) kinds[iss.kind]=(kinds[iss.kind]||0)+1;
    \\    nodes.push({
    \\      id:i, name:fn.name, count:fn.count, issues:fn.issues,
    \\      x:Math.random()*800+100, y:Math.random()*600+100,
    \\      vx:0, vy:0,
    \\      r:8+Math.sqrt(fn.count/maxCnt)*22,
    \\      color:SEV[worstSev.severity]||'#666',
    \\      kindKeys:Object.keys(kinds),
    \\    });
    \\  }
    \\  // Edges: limit to MAX_EDGES=1500 to avoid O(N^2) DOM explosion
    \\  const prefixMap = {};
    \\  for (const n of nodes) {
    \\    const p = n.name.split('_')[0];
    \\    if (!prefixMap[p]) prefixMap[p] = [];
    \\    prefixMap[p].push(n.id);
    \\  }
    \\  let edgeCount = 0; const MAX_EDGES = 1500;
    \\  for (const arr of Object.values(prefixMap)) {
    \\    if (arr.length < 2 || edgeCount >= MAX_EDGES) continue;
    \\    const limit = Math.min(arr.length * 2, MAX_EDGES - edgeCount);
    \\    let k = 0;
    \\    for (let i = 0; i < arr.length && k < limit; i++) {
    \\      for (let j = i+1; j < arr.length && k < limit; j++, k++) {
    \\        edges.push({source:arr[i], target:arr[j]}); edgeCount++;
    \\      }
    \\    }
    \\  }
    \\}
    \\
    \\function runForceLayout(iterations=80) {
    \\  if (nodes.length === 0) return;
    \\  const W=900, H=650, N=nodes.length;
    \\  const GRID_SIZE = 120;
    \\  for (let iter = 0; iter < iterations; iter++) {
    \\    // Spatial hash grid: O(N) repulsion instead of O(N^2)
    \\    const grid = new Map();
    \\    for (let i = 0; i < N; i++) {
    \\      const gx=Math.floor(nodes[i].x/GRID_SIZE), gy=Math.floor(nodes[i].y/GRID_SIZE);
    \\      const key=gx+','+gy;
    \\      if (!grid.has(key)) grid.set(key, []);
    \\      grid.get(key).push(i);
    \\    }
    \\    // Repulsion: only check 9-cell neighborhood
    \\    for (let i = 0; i < N; i++) {
    \\      const gx=Math.floor(nodes[i].x/GRID_SIZE), gy=Math.floor(nodes[i].y/GRID_SIZE);
    \\      for (let dx=-1;dx<=1;dx++) for (let dy=-1;dy<=1;dy++) {
    \\        const cell=grid.get((gx+dx)+','+(gy+dy));
    \\        if (!cell) continue;
    \\        for (const j of cell) { if (j<=i) continue;
    \\          const rx=nodes[j].x-nodes[i].x, ry=nodes[j].y-nodes[i].y;
    \\          const d=Math.max(Math.sqrt(rx*rx+ry*ry),0.5);
    \\          const f=1800/(d*d); nodes[i].vx-=rx/d*f; nodes[i].vy-=ry/d*f;
    \\          nodes[j].vx+=rx/d*f; nodes[j].vy+=ry/d*f;
    \\        }
    \\      }
    \\    }
    \\    // Attraction along edges (stronger spring for fewer iters)
    \\    for (const e of edges) {
    \\      const s=nodes[e.source], t=nodes[e.target];
    \\      const dx=t.x-s.x, dy=t.y-s.y;
    \\      const d=Math.max(Math.sqrt(dx*dx+dy*dy),1);
    \\      const f=(d-100)*0.02;
    \\      s.vx+=dx/d*f; s.vy+=dy/d*f; t.vx-=dx/d*f; t.vy-=dy/d*f;
    \\    }
    \\    // Center gravity + damping
    \\    for (const n of nodes) { n.vx+=(W/2-n.x)*0.01; n.vy+=(H/2-n.y)*0.01; n.vx*=0.82; n.vy*=0.82; n.x+=n.vx; n.y+=n.vy; }
    \\  }
    \\}
    \\
    \\function renderGraph() {
    \\  // Batch-render: build single HTML string (10x faster than individual DOM ops)
    \\  let html = '';
    \\  for (const e of edges) {
    \\    html += '<line x1="'+nodes[e.source].x.toFixed(0)+'" y1="'+nodes[e.source].y.toFixed(0)+
    \\      '" x2="'+nodes[e.target].x.toFixed(0)+'" y2="'+nodes[e.target].y.toFixed(0)+
    \\      '" stroke="#30363d" stroke-width="1" opacity="0.35"/>';
    \\  }
    \\  const nm = {};
    \\  for (const n of nodes) {
    \\    const fs = n.r > 16 ? '11' : '9';
    \\    html += '<g transform="translate('+n.x.toFixed(0)+','+n.y.toFixed(0)+')" style="cursor:pointer" data-id="'+n.id+'">'+
    \\      '<circle r="'+n.r+'" fill="'+n.color+'" fill-opacity="0.85" stroke="#fff" stroke-width="2"/>'+
    \\      '<text fill="#fff" font-size="'+fs+'" text-anchor="middle" dominant-baseline="middle" pointer-events="none">'+esc(n.name.slice(0,10))+'</text>';
    \\    if (n.count > 1) {
    \\      const br = Math.min(n.r * 0.4, 10);
    \\      html += '<circle cx="'+(n.r*0.7).toFixed(0)+'" cy="'+(-n.r*0.7).toFixed(0)+'" r="'+br+'" fill="#e74c3c" stroke="#fff" stroke-width="1"/>'+
    \\        '<text x="'+(n.r*0.7).toFixed(0)+'" y="'+(-n.r*0.7).toFixed(0)+'" fill="#fff" font-size="9" font-weight="bold" text-anchor="middle" dominant-baseline="middle" pointer-events="none">'+n.count+'</text>';
    \\    }
    \\    html += '</g>';
    \\    nm[n.id] = n;
    \\  }
    \\  g.innerHTML = html;
    \\  // Event delegation: 3 listeners total instead of 1800
    \\  g.onmouseover = function(ev) {
    \\    const grp = ev.target.closest ? ev.target.closest('g[data-id]') : null;
    \\    if (!grp) return; const n = nm[parseInt(grp.dataset.id)]; if (!n) return;
    \\    const t=document.getElementById('tooltip');t.style.display='block';t.style.left=(ev.pageX+15)+'px';t.style.top=(ev.pageY+10)+'px';
    \\    t.innerHTML='<b style=font-size:14px>'+esc(n.name)+'</b><br>'+(n.kindKeys.map(k=>KIND[k]?KIND[k].icon:'?').join(' '))+' | <b>'+n.count+'</b> issues<br>Click → details';
    \\  };
    \\  g.onmouseout = function(ev) { if(!ev.relatedTarget||!g.contains(ev.relatedTarget)) document.getElementById('tooltip').style.display='none'; };
    \\  g.onclick = function(ev) {
    \\    const grp = ev.target.closest ? ev.target.closest('g[data-id]') : null;
    \\    if (!grp) return; selectNode(nm[parseInt(grp.dataset.id)]);
    \\  };
    \\  fitView();
    \\}
    \\
    \\function selectNode(n) {
    \\  highlightNode(n.id);
    \\  showDetailPanel(n);
    \\}
    \\
    \\function highlightNode(id) {
    \\  document.querySelectorAll('.node-circle').forEach(c=>{ c.setAttribute('stroke-width','2'); c.setAttribute('stroke','#fff'); });
    \\  const el=g.querySelector('[data-id="'+id+'"] circle');
    \\  if(el){el.setAttribute('stroke-width','4');el.setAttribute('stroke','#58a6ff');}
    \\}
    \\
    \\function showDetailPanel(n) {
    \\  const p=document.getElementById('detail-panel');
    \\  let h='<h3 style=color:#58a6ff;margin-bottom:8px>'+esc(n.name)+' <span style=font-size:13px;color:#888>('+(n.kindKeys.map(k=>KIND[k]?KIND[k].icon:'?').join(''))+' '+n.count+')</span></h3>';
    \\  h+='<div class=lifecycle>';
    \\  const order=['memory_leak','malloc_unchecked','borrow_escape','use_after_free','invalid_free','double_free'];
    \\  const byKind={}; for(const iss of n.issues){if(!byKind[iss.kind])byKind[iss.kind]=[];byKind[iss.kind].push(iss);}
    \\  let any=false;
    \\  for(const k of order){const items=byKind[k]||[];if(!items.length)continue;any=true;
    \\    const info=KIND[k]||{c:'#666',icon:'?',label:k};
    \\    h+='<div class=lifecycle-group><div class=lifecycle-header style="border-left:4px solid '+info.c+'"><span>'+info.icon+'</span><b>'+(info.label||k)+'</b> ('+items.length+')</div>';
    \\    for(const iss of items){const sc=SEV[iss.severity]||'#888';
    \\    h+='<div class=lifecycle-item onclick="showIssueTip(event,this)" data-msg="'+esc(iss.msg)+'" data-line='+iss.line+' data-sev='+iss.severity+' data-conf='+iss.confidence+'>';
    \\    h+='<span class=sev-dot style=background:'+sc+'></span><span class=line-num>L'+iss.line+'</span>';
    \\    h+='<span class=issue-msg>'+esc(iss.msg.length>80?iss.msg.slice(0,77)+'...':iss.msg)+'</span>';
    \\    h+='<span class=conf>'+(iss.confidence/100).toFixed(0)+'%</span></div>';}
    \\    h+='</div>';}
    \\  if(!any)h+='<p style=color:#888>No memory issues.</p>';h+='</div>';
    \\  p.innerHTML=h;
    \\  // Also highlight in sidebar
    \\  document.querySelectorAll('.func-item').forEach(el=>el.classList.toggle('selected',el.dataset.fn===n.name));
    \\}
    \\
    \\function showTooltip(ev, n) {
    \\  const t=document.getElementById('tooltip');
    \\  t.style.display='block';t.style.left=(ev.pageX+15)+'px';t.style.top=(ev.pageY+10)+'px';
    \\  const icons=n.kindKeys.map(k=>KIND[k]?KIND[k].icon:'?').join(' ');
    \\  t.innerHTML='<b style=font-size:14px>'+esc(n.name)+'</b><br>'+
    \\    icons+' | <b>'+n.count+'</b> issues<br>Click for details →';
    \\}
    \\function hideTooltip(){document.getElementById('tooltip').style.display='none';}
    \\function showIssueTip(ev,el){
    \\  const t=document.getElementById('tooltip');t.style.display='block';t.style.left=(ev.pageX+15)+'px';t.style.top=(ev.pageY+10)+'px';
    \\  t.innerHTML='<b>Line '+el.dataset.line+'</b> '+el.dataset.sev+' | '+(parseInt(el.dataset.conf)/100).toFixed(2)+'<br>'+el.dataset.msg;
    \\  ev.stopPropagation();
    \\}
    \\
    \\function renderSummary(){
    \\  const sk=D.summary.by_kind||{};const mv=Math.max(...Object.values(sk),1);
    \\  let h='<div style=display:flex;gap:8px;flex-wrap:wrap;padding:4px 0>';
    \\  for(const [k,v]of Object.entries(KIND)){const cnt=sk[k]||0;if(!cnt)continue;
    \\    const w=Math.max(cnt/mv*120,2);
    \\    h+='<div title="'+(v.label||k)+': '+cnt+'" style="display:flex;align-items:center;gap:4px"><span>'+v.icon+'</span>';
    \\    h+='<div style=background:'+v.c+';width:'+w+'px;height:16px;border-radius:2px></div>';
    \\    h+='<span style=color:#aaa;font-size:11px>'+cnt+'</span></div>';}
    \\  h+='</div>';document.getElementById('summary-panel').innerHTML=h;
    \\  document.getElementById('stats').innerHTML='<b>'+D.meta.total_issues+'</b> issues in <b>'+D.meta.function_count+'</b> functions';
    \\}
    \\
    \\function renderSidebar(){
    \\  const c=document.getElementById('func-tree');let h='';
    \\  const sorted=[...D.functions].sort((a,b)=>b.count-a.count);
    \\  for(const fn of sorted){
    \\    const ws=fn.issues.reduce((a,b)=>sevOrder(a.severity)<sevOrder(b.severity)?a:b,{severity:'low'});
    \\    const ks={};for(const i of fn.issues)ks[i.kind]=(ks[i.kind]||0)+1;
    \\    const ki=Object.keys(ks).map(k=>KIND[k]?KIND[k].icon:'?').join('');
    \\    h+='<div class=func-item data-fn="'+esc(fn.name)+'" onclick="clickSidebar(\''+esc(fn.name)+'\')">';
    \\    h+='<span class=func-badge style="background:'+(SEV[ws.severity]||'#666')+'">'+fn.count+'</span>';
    \\    h+='<span class=func-name>'+esc(fn.name)+'</span><span class=func-icons>'+ki+'</span></div>';
    \\  }c.innerHTML=h;
    \\}
    \\function clickSidebar(name){const n=nodes.find(x=>x.name===name);if(n)selectNode(n);}
    \\
    \\function sevOrder(s){return s==='critical'?0:s==='high'?1:s==='medium'?2:3;}
    \\function esc(s){return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');}
    \\function filterFunctions(){
    \\  const q=(document.getElementById('search').value||'').toLowerCase();
    \\  document.querySelectorAll('.func-item').forEach(el=>{
    \\    el.style.display=el.dataset.fn.toLowerCase().includes(q)?'':'none';
    \\  });
    \\  // Also dim non-matching nodes in graph
    \\  g.querySelectorAll('g[data-id]').forEach(el=>{
    \\    const n=nodes[parseInt(el.dataset.id)];
    \\    el.style.opacity=(n&&n.name.toLowerCase().includes(q))?1:0.15;
    \\  });
    \\}
    \\
    \\function onWheel(e){e.preventDefault();const f=e.deltaY<0?1.1:0.9;transform.k*=f;transform.k=Math.max(0.1,Math.min(6,transform.k));applyTransform();}
    \\function onMouseDown(e){
    \\  dragging=true;lastPos={x:e.clientX,y:e.clientY};
    \\  const tgt=e.target.closest('g[data-id]');
    \\  if(tgt){dragNode=nodes[parseInt(tgt.dataset.id)];dragNode.px=dragNode.x;dragNode.py=dragNode.y;}
    \\  else dragNode=null;
    \\  svg.style.cursor=dragNode?'grabbing':'grab';
    \\}
    \\function onMouseMove(e){
    \\  if(!dragging||!lastPos)return;
    \\  if(dragNode){dragNode.x=dragNode.px+(e.clientX-lastPos.x)/transform.k;dragNode.y=dragNode.py+(e.clientY-lastPos.y)/transform.k;renderGraph();highlightNode(dragNode.id);return;}
    \\  transform.x+=e.clientX-lastPos.x;transform.y+=e.clientY-lastPos.y;lastPos={x:e.clientX,y:e.clientY};applyTransform();
    \\}
    \\function onMouseUp(){dragging=false;lastPos=null;dragNode=null;svg.style.cursor='grab';}
    \\function applyTransform(){g.setAttribute('transform','translate('+transform.x+','+transform.y+') scale('+transform.k+')');}
    \\function fitView(){
    \\  if(nodes.length===0)return;
    \\  let minX=Infinity,minY=Infinity,maxX=-Infinity,maxY=-Infinity;
    \\  for(const n of nodes){minX=Math.min(minX,n.x-n.r);minY=Math.min(minY,n.y-n.r);maxX=Math.max(maxX,n.x+n.r);maxY=Math.max(maxY,n.y+n.r);}
    \\  const cw=svg.clientWidth||1000,ch=svg.clientHeight||700,pad=60;
    \\  const sx=(cw-pad*2)/(maxX-minX||1),sy=(ch-pad*2)/(maxY-minY||1);
    \\  const k=Math.min(sx,sy,1.8);
    \\  transform={x:pad-(minX*k),y:pad-(minY*k),k};applyTransform();
    \\}
    \\
    \\document.addEventListener('click',()=>{document.getElementById('tooltip').style.display='none';});
    \\init();
;

// ═══════════════════════════════════════════════════════════════
// Tests
// ═══════════════════════════════════════════════════════════════

test "GraphVisualizer init/deinit" {
    var viz = try GraphVisualizer.init(std.testing.allocator);
    defer viz.deinit();
    try std.testing.expect(viz.buf.items.len == 0);
}

test "GraphVisualizer exports valid HTML" {
    var viz = try GraphVisualizer.init(std.testing.allocator);
    defer viz.deinit();

    // Use new JSON-based pipeline (no MemoryGraph dependency)
    const test_issues = [_]GraphIssue{
        .{ .kind = .memory_leak, .message = "test leak", .function = "test_func", .severity = "high", .confidence = 0.9, .line = 42 },
        .{ .kind = .use_after_free, .message = "test uaf", .function = "test_func", .severity = "critical", .confidence = 0.85, .line = 77 },
    };

    try viz.exportIssuesHtml(&test_issues, "/tmp/test_graph.json", "/tmp/test_memory.html");

    // Verify key HTML markers exist
    const html = viz.buf.items;
    try std.testing.expect(std.mem.indexOf(u8, html, "<!DOCTYPE html>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "<svg") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "OmniScope Memory Graph") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "_graphData") != null);
}
