//! Semantic resolution tree - a unified data structure for cross-language
//! semantic analysis.
//!
//! This module provides a generic semantic tree that can store semantic
//! information about code constructs across different languages. It's designed
//! to be language-agnostic while supporting language-specific patterns through
//! the pattern registry system.

const std = @import("std");
const c = @import("../ir/llvm_raw.zig").c;

/// Semantic kind — what the SRT needs to answer:
/// "Can this value be explained away by language semantics?"
///
/// Extended from 4 to 11 variants to cover Rust Nomicon patterns:
/// - interior_mutability: UnsafeCell/Once/OnceLock/Cell/RefCell/Mutex/RwLock/Atomic*
/// - heap_provenance: Box/Arc/Vec/String heap-owning pointers
/// - global_provenance: static/const/&'static
/// - file_operation: unlink/close/open/rename
/// - network_operation: socket/bind/connect/listen
/// - process_operation: fork/execve/exit
/// - raii_drop_release: compiler-inserted Drop/dealloc
pub const SemanticKind = enum(u8) {
    // ── Existing (kept) ──
    unknown,
    allocation,
    release,
    provenance,

    // ── Interior mutability (covers F2: write_to_immutable FP) ──
    interior_mutability,

    // ── Provenance细化 (covers F1: borrow_escape FP) ──
    heap_provenance,
    global_provenance,

    // ── Syscall semantics (covers F3/F5) ──
    file_operation,
    network_operation,
    process_operation,

    // ── RAII drop (covers F4: use_after_free FP) ──
    raii_drop_release,
};

/// A semantic resolution - the result of applying a pattern to a node
pub const Resolution = struct {
    kind: SemanticKind,
    confidence: f32,
    nomicon_chapter: ?[]const u8,
    evidence: []const u8,
    pattern_id: ?usize,
};

/// Reference to a value (pointer, instruction, etc.)
pub const ValueRef = u64;

/// A node in the semantic tree
pub const SemanticNode = struct {
    id: usize,
    kind: SemanticKind,
    name: []const u8,
    value_ref: ValueRef,
    location: Location,
    resolutions: std.ArrayListUnmanaged(Resolution),
    children: std.ArrayListUnmanaged(usize),
    parent: ?usize,

    const Self = @This();

    pub fn init(
        allocator: std.mem.Allocator,
        id: usize,
        kind: SemanticKind,
        name: []const u8,
        value_ref: ValueRef,
        location: Location,
    ) !Self {
        return Self{
            .id = id,
            .kind = kind,
            .name = try allocator.dupe(u8, name),
            .value_ref = value_ref,
            .location = location,
            .resolutions = std.ArrayListUnmanaged(Resolution){},
            .children = std.ArrayListUnmanaged(usize){},
            .parent = null,
        };
    }

    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        self.location.deinit(allocator);
        self.resolutions.deinit(allocator);
        self.children.deinit(allocator);
    }

    pub fn addResolution(self: *Self, allocator: std.mem.Allocator, resolution: Resolution) !void {
        try self.resolutions.append(allocator, resolution);
    }

    pub fn addChild(self: *Self, allocator: std.mem.Allocator, child_id: usize) !void {
        try self.children.append(allocator, child_id);
    }
};

/// Source location information
pub const Location = struct {
    file: []const u8,
    line: u32,
    column: u32,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, file: []const u8, line: u32, column: u32) !Self {
        return Self{
            .file = try allocator.dupe(u8, file),
            .line = line,
            .column = column,
        };
    }

    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        allocator.free(self.file);
    }
};

/// Semantic resolution tree - stores all semantic nodes
pub const SemanticTree = struct {
    allocator: std.mem.Allocator,
    nodes: std.ArrayListUnmanaged(SemanticNode),
    value_to_node: std.AutoHashMap(ValueRef, usize),

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .nodes = std.ArrayListUnmanaged(SemanticNode){},
            .value_to_node = std.AutoHashMap(ValueRef, usize).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.nodes.items) |*node| {
            node.deinit(self.allocator);
        }
        self.nodes.deinit(self.allocator);
        self.value_to_node.deinit();
    }

    pub fn addNode(
        self: *Self,
        kind: SemanticKind,
        name: []const u8,
        value_ref: ValueRef,
        location_line: u32,
    ) !usize {
        const id = self.nodes.items.len;
        const location = try Location.init(self.allocator, "unknown", location_line, 0);
        const node = try SemanticNode.init(
            self.allocator,
            id,
            kind,
            name,
            value_ref,
            location,
        );
        try self.nodes.append(self.allocator, node);
        try self.value_to_node.put(value_ref, id);
        return id;
    }

    pub fn getNode(self: *const Self, id: usize) ?*const SemanticNode {
        if (id < self.nodes.items.len) {
            return &self.nodes.items[id];
        }
        return null;
    }

    pub fn getNodeByValue(self: *const Self, value_ref: ValueRef) ?*const SemanticNode {
        const id = self.value_to_node.get(value_ref) orelse return null;
        return self.getNode(id);
    }

    pub fn addResolution(self: *Self, node_id: usize, resolution: Resolution) !void {
        if (node_id < self.nodes.items.len) {
            try self.nodes.items[node_id].addResolution(self.allocator, resolution);
        }
    }

    pub fn getResolutions(self: *const Self, node_id: usize) []const Resolution {
        if (node_id < self.nodes.items.len) {
            return self.nodes.items[node_id].resolutions.items;
        }
        return &.{};
    }

    pub fn getNodes(self: *const Self) []const SemanticNode {
        return self.nodes.items;
    }

    pub fn findNodesByKind(_self: *const Self, _kind: SemanticKind) []const SemanticNode {
        _ = _self;
        _ = _kind;
        return &.{};
    }

    pub fn findNodesByName(_self: *const Self, _name: []const u8) []const SemanticNode {
        _ = _self;
        _ = _name;
        return &.{};
    }

    // ── New unified query API ──────────────────────────────────────

    pub fn hasKind(self: *const Self, value_ref: ValueRef, kind: SemanticKind) ?Resolution {
        const node = self.getNodeByValue(value_ref) orelse return null;
        var best: ?Resolution = null;
        for (node.resolutions.items) |r| {
            if (r.kind == kind) {
                if (best == null or r.confidence > best.?.confidence) {
                    best = r;
                }
            }
        }
        return best;
    }

    pub fn allResolutions(self: *const Self, value_ref: ValueRef) []const Resolution {
        const node = self.getNodeByValue(value_ref) orelse return &.{};
        return node.resolutions.items;
    }

    pub fn recordResolution(
        self: *Self,
        value_ref: ValueRef,
        kind: SemanticKind,
        confidence: f32,
        nomicon_chapter: ?[]const u8,
        evidence: []const u8,
    ) !void {
        const node_id = blk: {
            if (self.value_to_node.get(value_ref)) |id| {
                break :blk id;
            } else {
                break :blk try self.addNode(kind, "auto", value_ref, 0);
            }
        };
        try self.addResolution(node_id, Resolution{
            .kind = kind,
            .confidence = confidence,
            .nomicon_chapter = nomicon_chapter,
            .evidence = evidence,
            .pattern_id = null,
        });
    }

    // ── Trace functions for def-use chain analysis ──────────────────

    pub fn traceToHeapProvenance(
        self: *const Self,
        value: c.LLVMValueRef,
        max_depth: u32,
    ) bool {
        var current = value;
        var depth: u32 = 0;
        
        while (depth < max_depth) : (depth += 1) {
            const ref = @intFromPtr(current);
            
            // Check SRT for this value
            if (self.hasKind(ref, .heap_provenance) != null) {
                std.debug.print("[TRACE] Found heap_provenance at depth {d}, ref={d}\n", .{depth, ref});
                return true;
            }
            if (self.hasKind(ref, .global_provenance) != null) {
                std.debug.print("[TRACE] Found global_provenance at depth {d}, ref={d}\n", .{depth, ref});
                return true;
            }
            
            if (@intFromPtr(c.LLVMIsAInstruction(current)) == 0) {
                // Check what type of value this is
                const is_global = @intFromPtr(c.LLVMIsAGlobalValue(current)) != 0;
                const is_arg = @intFromPtr(c.LLVMIsAArgument(current)) != 0;
                const is_const = @intFromPtr(c.LLVMIsAConstant(current)) != 0;
                const value_kind = c.LLVMGetValueKind(current);
                std.debug.print("[TRACE] Not an instruction at depth {d}: is_global={}, is_arg={}, is_const={}, value_kind={d}\n", .{depth, is_global, is_arg, is_const, value_kind});
                
                // If it's a global variable, it might have heap_provenance
                if (is_global) {
                    const global_ref = @intFromPtr(current);
                    if (self.hasKind(global_ref, .heap_provenance) != null) {
                        std.debug.print("[TRACE] Found heap_provenance on global variable\n", .{});
                        return true;
                    }
                }
                
                // If it's a function argument, it should already be marked
                // by forward propagation in ch09
                if (is_arg) {
                    std.debug.print("[TRACE] Function argument — check SRT for pre-marked provenance\n", .{});
                }
                break;
            }
            
            const opcode = c.LLVMGetInstructionOpcode(current);
            const opcode_name = getOpcodeName(opcode);
            std.debug.print("[TRACE] Depth {d}: opcode={s} ref={d}\n", .{depth, opcode_name, ref});
            
            if (opcode == c.LLVMGetElementPtr or opcode == c.LLVMLoad) {
                const base = c.LLVMGetOperand(current, 0);
                if (@intFromPtr(base) == 0) break;
                std.debug.print("[TRACE]   -> following operand 0 to ref={d}\n", .{@intFromPtr(base)});
                current = base;
                continue;
            }
            
            if (opcode == c.LLVMCall or opcode == c.LLVMInvoke) {
                // Check if this call instruction itself has heap_provenance
                if (self.hasKind(ref, .heap_provenance) != null) {
                    std.debug.print("[TRACE] Found heap_provenance on call instruction\n", .{});
                    return true;
                }
                std.debug.print("[TRACE] Call instruction without heap_provenance, stopping\n", .{});
                break;
            }
            
            if (opcode == c.LLVMPHI) {
                const num_incoming = c.LLVMCountIncoming(current);
                std.debug.print("[TRACE] PHI node with {d} incoming values\n", .{num_incoming});
                var i: u32 = 0;
                while (i < num_incoming) : (i += 1) {
                    const incoming = c.LLVMGetIncomingValue(current, i);
                    if (self.traceToHeapProvenance(incoming, max_depth - depth - 1)) {
                        return true;
                    }
                }
                break;
            }
            
            if (opcode == c.LLVMBitCast or opcode == c.LLVMIntToPtr) {
                const operand = c.LLVMGetOperand(current, 0);
                if (@intFromPtr(operand) == 0) break;
                std.debug.print("[TRACE]   -> following bitcast/inttoptr operand to ref={d}\n", .{@intFromPtr(operand)});
                current = operand;
                continue;
            }
            
            std.debug.print("[TRACE] Unhandled opcode {s}, stopping\n", .{opcode_name});
            break;
        }
        
        std.debug.print("[TRACE] No heap_provenance found after {d} steps\n", .{depth});
        return false;
    }
    
    fn getOpcodeName(opcode: c_uint) []const u8 {
        return switch (opcode) {
            c.LLVMRet => "ret",
            c.LLVMBr => "br",
            c.LLVMSwitch => "switch",
            c.LLVMIndirectBr => "indirectbr",
            c.LLVMInvoke => "invoke",
            c.LLVMUnreachable => "unreachable",
            c.LLVMCallBr => "callbr",
            c.LLVMFNeg => "fneg",
            c.LLVMAdd => "add",
            c.LLVMFAdd => "fadd",
            c.LLVMSub => "sub",
            c.LLVMFSub => "fsub",
            c.LLVMMul => "mul",
            c.LLVMFMul => "fmul",
            c.LLVMUDiv => "udiv",
            c.LLVMSDiv => "sdiv",
            c.LLVMFDiv => "fdiv",
            c.LLVMURem => "urem",
            c.LLVMSRem => "srem",
            c.LLVMFRem => "frem",
            c.LLVMShl => "shl",
            c.LLVMLShr => "lshr",
            c.LLVMAShr => "ashr",
            c.LLVMAnd => "and",
            c.LLVMOr => "or",
            c.LLVMXor => "xor",
            c.LLVMAlloca => "alloca",
            c.LLVMLoad => "load",
            c.LLVMStore => "store",
            c.LLVMGetElementPtr => "gep",
            c.LLVMTrunc => "trunc",
            c.LLVMZExt => "zext",
            c.LLVMSExt => "sext",
            c.LLVMFPToUI => "fptoui",
            c.LLVMFPToSI => "fptosi",
            c.LLVMUIToFP => "uitofp",
            c.LLVMSIToFP => "sitofp",
            c.LLVMFPTrunc => "fptrunc",
            c.LLVMFPExt => "fpext",
            c.LLVMPtrToInt => "ptrtoint",
            c.LLVMIntToPtr => "inttoptr",
            c.LLVMBitCast => "bitcast",
            c.LLVMAddrSpaceCast => "addrspacecast",
            c.LLVMICmp => "icmp",
            c.LLVMFCmp => "fcmp",
            c.LLVMPHI => "phi",
            c.LLVMCall => "call",
            c.LLVMSelect => "select",
            c.LLVMUserOp1 => "userop1",
            c.LLVMUserOp2 => "userop2",
            c.LLVMVAArg => "va_arg",
            c.LLVMExtractElement => "extractelement",
            c.LLVMInsertElement => "insertelement",
            c.LLVMShuffleVector => "shufflevector",
            c.LLVMExtractValue => "extractvalue",
            c.LLVMInsertValue => "insertvalue",
            c.LLVMFreeze => "freeze",
            c.LLVMFence => "fence",
            c.LLVMAtomicCmpXchg => "cmpxchg",
            c.LLVMAtomicRMW => "atomicrmw",
            c.LLVMResume => "resume",
            c.LLVMLandingPad => "landingpad",
            c.LLVMCleanupRet => "cleanupret",
            c.LLVMCatchRet => "catchret",
            c.LLVMCatchPad => "catchpad",
            c.LLVMCleanupPad => "cleanuppad",
            else => "unknown",
        };
    }

    pub fn traceToInteriorMutability(
        self: *const Self,
        value: c.LLVMValueRef,
        max_depth: u32,
    ) bool {
        var current = value;
        var depth: u32 = 0;
        
        while (depth < max_depth) : (depth += 1) {
            const ref = @intFromPtr(current);
            
            if (self.hasKind(ref, .interior_mutability) != null) return true;
            
            if (@intFromPtr(c.LLVMIsAInstruction(current)) == 0) break;
            
            const opcode = c.LLVMGetInstructionOpcode(current);
            
            if (opcode == c.LLVMGetElementPtr or opcode == c.LLVMLoad) {
                const base = c.LLVMGetOperand(current, 0);
                if (@intFromPtr(base) == 0) break;
                current = base;
                continue;
            }
            
            if (opcode == c.LLVMBitCast) {
                const operand = c.LLVMGetOperand(current, 0);
                if (@intFromPtr(operand) == 0) break;
                current = operand;
                continue;
            }
            
            break;
        }
        
        return false;
    }
};

test "Semantic tree basic functionality" {
    const allocator = std.testing.allocator;

    var tree = SemanticTree.init(allocator);
    defer tree.deinit();

    const alloc_id = try tree.addNode(.allocation, "malloc", 0x1000, 10);
    try std.testing.expect(alloc_id == 0);

    try tree.addResolution(alloc_id, Resolution{
        .kind = .release,
        .confidence = 0.95,
        .nomicon_chapter = "Ch6 OBRM",
        .evidence = "test_data",
        .pattern_id = 0,
    });

    const node = tree.getNode(alloc_id);
    try std.testing.expect(node != null);
    try std.testing.expect(std.mem.eql(u8, node.?.name, "malloc"));

    const resolutions = tree.getResolutions(alloc_id);
    try std.testing.expect(resolutions.len == 1);
    try std.testing.expect(resolutions[0].kind == .release);
    try std.testing.expect(resolutions[0].confidence == 0.95);
}

test "hasKind and recordResolution" {
    const allocator = std.testing.allocator;

    var tree = SemanticTree.init(allocator);
    defer tree.deinit();

    try tree.recordResolution(0x2000, .heap_provenance, 0.90, "Ch9 Vec/Box", "alloca DI=Box<ClientSession>");

    const result = tree.hasKind(0x2000, .heap_provenance);
    try std.testing.expect(result != null);
    try std.testing.expect(result.?.kind == .heap_provenance);
    try std.testing.expect(result.?.confidence == 0.90);

    const not_found = tree.hasKind(0x2000, .interior_mutability);
    try std.testing.expect(not_found == null);
}
