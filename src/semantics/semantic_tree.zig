//! Semantic resolution tree - a unified data structure for cross-language
//! semantic analysis.
//!
//! This module provides a generic semantic tree that can store semantic
//! information about code constructs across different languages. It's designed
//! to be language-agnostic while supporting language-specific patterns through
//! the pattern registry system.

const std = @import("std");
const c = @import("../ir/llvm_raw.zig").c;
const log = @import("../common/log.zig");

/// Semantic kind — what the SRT needs to answer:
/// "Can this value be explained away by language semantics?"
///
/// Extended from 4 to 15 variants to cover bun FP patterns (R-0~R-8):
/// - readonly_param/mutable_param: LLVM parameter attributes (R-0, 1877 FP main cause)
/// - interior_mutability: UnsafeCell/Once/OnceLock/Cell/RefCell/Mutex/RwLock/Atomic*
/// - heap_provenance: Box/Arc/Rc/Vec/String/*mut heap-owning pointers (R-1)
/// - global_provenance: static/const/&'static
/// - file_operation/network_operation/process_operation: POSIX syscall classes (R-4)
/// - raii_drop_release: compiler-inserted Drop/dealloc (R-3)
/// - into_raw_transfer: Box/CString/Vec::into_raw ownership transfer (R-6)
/// - library_release: mimalloc/zlib/openssl/sqlite library dealloc (R-7)
pub const SemanticKind = enum(u16) {
    // ── Existing (kept) ──
    unknown,
    allocation,
    release,
    provenance,

    // ── R-0: LLVM parameter attributes (covers F2: write_to_immutable 1877 FP) ──
    readonly_param, // function param has LLVM `readonly` attr → Rust &T / C const ptr
    mutable_param, // function param has no `readonly` attr → Rust &mut T / C plain ptr
    //   Writing to a mutable_param-derived pointer is legal &mut T write.
    //   Only writing to a readonly_param-derived pointer is a true immutable violation.

    // ── R-2: Interior mutability (covers remaining write_to_immutable FP) ──
    interior_mutability,

    // ── R-1: Provenance refinement (covers F1: borrow_escape 71 FP) ──
    heap_provenance, // value from __rust_alloc/malloc/Box::new; or alloca DI type
    //   is Box/Arc/Rc/Vec/String/*mut (SROA field load)
    global_provenance, // static/const/&'static/compile-time known source

    // ── R-6: Ownership transfer (covers F4: cross_language_free 4 FP) ──
    into_raw_transfer, // Box/CString/Vec::into_raw return value — ownership
    //   transferred to caller; subsequent C free() is legal

    // ── R-4: POSIX syscall semantics (cross_language_free / command_injection) ──
    file_operation, // unlink/close/open/rename/symlink/fcntl
    network_operation, // socket/bind/connect/listen/send/recv
    process_operation, // fork/vfork/execve/waitpid/kill

    // ── R-3: RAII drop (covers F3: use_after_free 3 FP) ──
    raii_drop_release, // compiler-inserted scope-end dealloc / drop_in_place
    //   function's dealloc. Includes Arc/Rc refcount conditional release.

    // ── R-7: Library-level allocator release (covers mimalloc/zlib/openssl/sqlite etc.) ──
    library_release, // mi_free/inflateEnd/EVP_CIPHER_CTX_free/sqlite3_finalize etc.
    //   cross_language_free detection hitting this kind → not reported

    // ── Nomicon Ch4: Unsafe type conversions (transmute, from_raw) ──
    unsafe_transmute, // bitcast/ptrtoint/inttoptr with size mismatch or invalid cast

    // ── Nomicon Ch5: Uninitialized memory usage (MaybeUninit::assume_init) ──
    uninit_memory_use, // Read from MaybeUninit field without proper initialization

    // ── Nomicon Ch8: Concurrency violations (Send/Sync trait abuse) ──
    send_sync_violation, // Sending non-Send type across thread boundary

    // ══════════════════════════════════════════
    // v0.2.0: Multi-language FFI semantics
    // ══════════════════════════════════════════

    // ─── Python (5 variants) ──────────────────────

    /// Py_INCREF / Py_IncRef call site
    python_refcount_inc = 100,

    /// Py_DECREF / Py_DecRef / Py_XDECREF call site
    python_refcount_dec = 101,

    /// Borrowed reference returned (PyList_GetItem, etc.)
    python_borrowed_ref = 102,

    /// Owned reference returned (PyList_New, etc.)
    python_owned_ref = 103,

    /// GIL acquisition/release (PyGILState_Ensure, etc.)
    python_gil_protected = 104,

    // ─── Go (4 variants) ────────────────────────────

    /// Deferred cleanup via 'defer' keyword
    go_defer_cleanup = 200,

    /// runtime.SetFinalizer call site
    go_finalizer = 201,

    /// CGo wrapper function (_Cgo_*)
    go_cgo_wrapper = 202,

    /// Runtime allocation (runtime.mallocgc, newobject)
    go_runtime_alloc = 203,

    // ─── C# (3 variants) ────────────────────────────

    /// SafeHandle / IDisposable pattern
    csharp_safe_handle = 300,

    /// P/Invoke interop call
    csharp_pinvoke = 301,

    /// Marshal class operation
    csharp_marshal_op = 302,

    // ─── Generic FFI (4 variants) ───────────────────

    /// Opaque handle from external library
    ffi_opaque_handle = 600,

    /// Resource acquisition pattern (RAII-like in C)
    ffi_resource_acquire = 601,

    /// Resource release pattern
    ffi_resource_release = 602,

    /// Callback/function pointer crossing language boundary
    ffi_callback_boundary = 603,

    _,
};

/// Target language for multi-language FFI semantics
pub const TargetLanguage = enum {
    python,
    go,
    csharp,

    pub fn displayName(self: TargetLanguage) []const u8 {
        return switch (self) {
            .python => "Python",
            .go => "Go",
            .csharp => "C#",
        };
    }
};

/// Helper methods for SemanticKind
pub const SemanticKindHelpers = struct {
    /// Check if this semantic belongs to a specific language
    pub fn language(kind: SemanticKind) ?TargetLanguage {
        return switch (kind) {
            // Python range
            .python_refcount_inc, .python_refcount_dec, .python_borrowed_ref, .python_owned_ref, .python_gil_protected => .python,

            // Go range
            .go_defer_cleanup, .go_finalizer, .go_cgo_wrapper, .go_runtime_alloc => .go,

            // C# range
            .csharp_safe_handle, .csharp_pinvoke, .csharp_marshal_op => .csharp,

            // Generic FFI - language-agnostic
            .ffi_opaque_handle, .ffi_resource_acquire, .ffi_resource_release, .ffi_callback_boundary => null,

            else => null, // Legacy/unclassified
        };
    }

    /// Check if this represents an owning operation (caller must free)
    pub fn isOwningOperation(kind: SemanticKind) bool {
        return switch (kind) {
            .python_owned_ref => true,
            .python_borrowed_ref => false,
            else => false, // Conservative default
        };
    }

    /// Human-readable category name
    pub fn categoryName(kind: SemanticKind) []const u8 {
        if (language(kind)) |lang| {
            return lang.displayName();
        }
        return "unknown";
    }
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
                log.debug("[TRACE] Found heap_provenance at depth {d}, ref={d}", .{ depth, ref });
                return true;
            }
            if (self.hasKind(ref, .global_provenance) != null) {
                log.debug("[TRACE] Found global_provenance at depth {d}, ref={d}", .{ depth, ref });
                return true;
            }

            if (@intFromPtr(c.LLVMIsAInstruction(current)) == 0) {
                // Check what type of value this is
                const is_global = @intFromPtr(c.LLVMIsAGlobalValue(current)) != 0;
                const is_arg = @intFromPtr(c.LLVMIsAArgument(current)) != 0;
                const is_const = @intFromPtr(c.LLVMIsAConstant(current)) != 0;
                const value_kind = c.LLVMGetValueKind(current);
                log.debug("[TRACE] Not an instruction at depth {d}: is_global={}, is_arg={}, is_const={}, value_kind={d}", .{ depth, is_global, is_arg, is_const, value_kind });

                // If it's a global variable, it might have heap_provenance
                if (is_global) {
                    const global_ref = @intFromPtr(current);
                    if (self.hasKind(global_ref, .heap_provenance) != null) {
                        log.debug("[TRACE] Found heap_provenance on global variable", .{});
                        return true;
                    }
                }

                // If it's a function argument, it should already be marked
                // by forward propagation in ch09
                if (is_arg) {
                    log.debug("[TRACE] Function argument — check SRT for pre-marked provenance", .{});
                }
                break;
            }

            const opcode = c.LLVMGetInstructionOpcode(current);
            const opcode_name = getOpcodeName(opcode);
            log.debug("[TRACE] Depth {d}: opcode={s} ref={d}", .{ depth, opcode_name, ref });

            if (opcode == c.LLVMGetElementPtr or opcode == c.LLVMLoad) {
                const base = c.LLVMGetOperand(current, 0);
                if (@intFromPtr(base) == 0) break;
                log.debug("[TRACE]   -> following operand 0 to ref={d}", .{@intFromPtr(base)});
                current = base;
                continue;
            }

            if (opcode == c.LLVMCall or opcode == c.LLVMInvoke) {
                // Check if this call instruction itself has heap_provenance
                if (self.hasKind(ref, .heap_provenance) != null) {
                    log.debug("[TRACE] Found heap_provenance on call instruction", .{});
                    return true;
                }
                log.debug("[TRACE] Call instruction without heap_provenance, stopping", .{});
                break;
            }

            if (opcode == c.LLVMPHI) {
                const num_incoming = c.LLVMCountIncoming(current);
                log.debug("[TRACE] PHI node with {d} incoming values", .{num_incoming});
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
                log.debug("[TRACE]   -> following bitcast/inttoptr operand to ref={d}", .{@intFromPtr(operand)});
                current = operand;
                continue;
            }

            log.debug("[TRACE] Unhandled opcode {s}, stopping", .{opcode_name});
            break;
        }

        log.debug("[TRACE] No heap_provenance found after {d} steps", .{depth});
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

// ══════════════════════════════════════════
// v0.2.0: Multi-language FFI semantics tests
// ══════════════════════════════════════════

test "SemanticKind - language detection for Python" {
    try std.testing.expectEqual(TargetLanguage.python, SemanticKindHelpers.language(.python_refcount_inc).?);
    try std.testing.expectEqual(TargetLanguage.python, SemanticKindHelpers.language(.python_refcount_dec).?);
    try std.testing.expectEqual(TargetLanguage.python, SemanticKindHelpers.language(.python_borrowed_ref).?);
    try std.testing.expectEqual(TargetLanguage.python, SemanticKindHelpers.language(.python_owned_ref).?);
    try std.testing.expectEqual(TargetLanguage.python, SemanticKindHelpers.language(.python_gil_protected).?);
}

test "SemanticKind - language detection for Go" {
    try std.testing.expectEqual(TargetLanguage.go, SemanticKindHelpers.language(.go_defer_cleanup).?);
    try std.testing.expectEqual(TargetLanguage.go, SemanticKindHelpers.language(.go_finalizer).?);
    try std.testing.expectEqual(TargetLanguage.go, SemanticKindHelpers.language(.go_cgo_wrapper).?);
    try std.testing.expectEqual(TargetLanguage.go, SemanticKindHelpers.language(.go_runtime_alloc).?);
}

test "SemanticKind - language detection for C#" {
    try std.testing.expectEqual(TargetLanguage.csharp, SemanticKindHelpers.language(.csharp_safe_handle).?);
    try std.testing.expectEqual(TargetLanguage.csharp, SemanticKindHelpers.language(.csharp_pinvoke).?);
    try std.testing.expectEqual(TargetLanguage.csharp, SemanticKindHelpers.language(.csharp_marshal_op).?);
}

test "SemanticKind - Generic FFI returns null (language-agnostic)" {
    try std.testing.expect(SemanticKindHelpers.language(.ffi_opaque_handle) == null);
    try std.testing.expect(SemanticKindHelpers.language(.ffi_resource_acquire) == null);
    try std.testing.expect(SemanticKindHelpers.language(.ffi_resource_release) == null);
    try std.testing.expect(SemanticKindHelpers.language(.ffi_callback_boundary) == null);
}

test "SemanticKind - legacy kinds return null" {
    try std.testing.expect(SemanticKindHelpers.language(.allocation) == null);
    try std.testing.expect(SemanticKindHelpers.language(.release) == null);
    try std.testing.expect(SemanticKindHelpers.language(.heap_provenance) == null);
}

test "SemanticKind - owning vs borrowing operations" {
    // Owning operations
    try std.testing.expect(SemanticKindHelpers.isOwningOperation(.python_owned_ref));

    // Borrowing/non-owning operations
    try std.testing.expect(!SemanticKindHelpers.isOwningOperation(.python_borrowed_ref));

    // Conservative default: most things are not owning
    try std.testing.expect(!SemanticKindHelpers.isOwningOperation(.allocation));
    try std.testing.expect(!SemanticKindHelpers.isOwningOperation(.python_refcount_inc));
}

test "SemanticKind - category names" {
    try std.testing.expectEqualStrings("Python", SemanticKindHelpers.categoryName(.python_refcount_inc));
    try std.testing.expectEqualStrings("Go", SemanticKindHelpers.categoryName(.go_defer_cleanup));
    try std.testing.expectEqualStrings("C#", SemanticKindHelpers.categoryName(.csharp_safe_handle));
    try std.testing.expectEqualStrings("unknown", SemanticKindHelpers.categoryName(.allocation));
}

test "TargetLanguage - display names" {
    try std.testing.expectEqualStrings("Python", TargetLanguage.python.displayName());
    try std.testing.expectEqualStrings("Go", TargetLanguage.go.displayName());
    try std.testing.expectEqualStrings("C#", TargetLanguage.csharp.displayName());
}

test "SemanticKind - enum value ranges are correct" {
    // Python range: 100-104
    try std.testing.expectEqual(@intFromEnum(SemanticKind.python_refcount_inc), 100);
    try std.testing.expectEqual(@intFromEnum(SemanticKind.python_gil_protected), 104);

    // Go range: 200-203
    try std.testing.expectEqual(@intFromEnum(SemanticKind.go_defer_cleanup), 200);
    try std.testing.expectEqual(@intFromEnum(SemanticKind.go_runtime_alloc), 203);

    // C# range: 300-302
    try std.testing.expectEqual(@intFromEnum(SemanticKind.csharp_safe_handle), 300);
    try std.testing.expectEqual(@intFromEnum(SemanticKind.csharp_marshal_op), 302);

    // Generic FFI range: 600-603
    try std.testing.expectEqual(@intFromEnum(SemanticKind.ffi_opaque_handle), 600);
    try std.testing.expectEqual(@intFromEnum(SemanticKind.ffi_callback_boundary), 603);
}
