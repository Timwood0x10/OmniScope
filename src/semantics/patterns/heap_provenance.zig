//! R-1: Heap Provenance Detector — SROA heap-field load via DI
//!
//! When LLVM's SROA pass breaks up a Box<T>/Arc<T>/Vec<String> etc. into
//! scalar fields, the alloca's DI metadata still retains the original
//! type name (e.g., "Box<ClientSession>"). This detector uses that
//! DI metadata to mark SROA-decomposed heap pointers.
//!
//! Three-layer provenance detection:
//!   Layer 1: Allocation call exact match (malloc, __rust_alloc, etc.)
//!   Layer 2: Alloca DI type prefix match (Box<, Arc<, Vec<, String, etc.)
//!   Layer 3: Use-def propagation (GEP, Load, BitCast chain)
//!
//! Covers: 71/1966 borrow_escape FP (R-1 SROA heap field).

const std = @import("std");
const c = @import("../../ir/llvm_raw.zig").c;
const llvm_safe = @import("../../ir/llvm_safe.zig");
const SemanticTree = @import("../semantic_tree.zig").SemanticTree;
const SemanticKind = @import("../semantic_tree.zig").SemanticKind;
const DiagnosticWriter = @import("../../pass/pass.zig").DiagnosticWriter;

/// Maximum depth for provenance tracing.
const MAX_TRACE_DEPTH: u32 = 16;

/// DI type name prefixes that indicate heap-owning types.
/// SROA may expose internal types like RawVec<, Unique<, NonNull<.
const HEAP_DI_PREFIXES = [_][]const u8{
    "Box<",      "alloc::boxed::Box<",
    "Arc<",      "alloc::sync::Arc<",
    "Rc<",       "alloc::rc::Rc<",
    "Vec<",      "alloc::vec::Vec<",
    "String",    "alloc::string::String",
    "*mut ",     "*const ",
    "RawVec<",   "Unique<",
    "NonNull<",  "HashMap<",
    "HashSet<",  "BTreeMap<",
    "BTreeSet<", "LinkedList<",
    "VecDeque<",
};

/// Allocation call suffixes with language classification.
const ALLOC_CALLS = [_]struct {
    suffix: []const u8,
}{
    // Rust global allocator (rustc ABI fixed symbols)
    .{ .suffix = "__rust_alloc" },
    .{ .suffix = "__rust_alloc_zeroed" },
    .{ .suffix = "__rust_realloc" },
    // C standard library
    .{ .suffix = "malloc" },
    .{ .suffix = "calloc" },
    .{ .suffix = "realloc" },
    .{ .suffix = "aligned_alloc" },
    // C++ new (Itanium mangling)
    .{ .suffix = "_Znwm" },
    .{ .suffix = "_Znam" },
    .{ .suffix = "_Znwj" },
    .{ .suffix = "_Znaj" },
    // Go runtime
    .{ .suffix = "runtime.alloc" },
    .{ .suffix = "_cgo_allocate" },
    // mimalloc / jemalloc
    .{ .suffix = "mi_malloc" },
    .{ .suffix = "mi_realloc" },
    .{ .suffix = "mi_zalloc" },
    .{ .suffix = "je_malloc" },
    .{ .suffix = "je_calloc" },
};

/// Provenance classification for a pointer value.
pub const Provenance = enum {
    heap,
    stack,
    global,
    unknown,
};

/// Detect heap provenance patterns and write to SRT.
/// Two-pass approach:
///   Pass 1: Scan all call + alloca instructions, write to SRT.
///   Pass 2 (lazy): Downstream passes call traceProvenance on demand.
pub fn detect(
    module: c.LLVMModuleRef,
    srt: *SemanticTree,
    diag: *DiagnosticWriter,
) !void {
    _ = diag;
    var func = c.LLVMGetFirstFunction(module);
    while (@intFromPtr(func) != 0) : (func = c.LLVMGetNextFunction(func)) {
        if (c.LLVMIsDeclaration(func) != 0) continue;

        var bb = c.LLVMGetFirstBasicBlock(func);
        while (@intFromPtr(bb) != 0) : (bb = c.LLVMGetNextBasicBlock(bb)) {
            var inst = c.LLVMGetFirstInstruction(bb);
            while (@intFromPtr(inst) != 0) : (inst = c.LLVMGetNextInstruction(inst)) {
                const opcode = c.LLVMGetInstructionOpcode(inst);

                // Layer 1: Allocation call exact match
                if (llvm_safe.isCallOrInvoke(opcode)) {
                    if (classifyAllocationCall(inst)) |prov| {
                        if (prov == .heap) {
                            try srt.recordResolution(
                                @intFromPtr(inst),
                                .heap_provenance,
                                0.98,
                                "R-1 alloc call",
                                getCalleeName(inst) orelse "unknown_alloc",
                            );
                        }
                    }
                }

                // Layer 2: Alloca DI type prefix match
                if (opcode == c.LLVMAlloca) {
                    if (classifyAllocaDI(inst)) |prov| {
                        if (prov == .heap) {
                            const di_name = findAllocaDITypeName(inst) orelse "unknown";
                            try srt.recordResolution(
                                @intFromPtr(inst),
                                .heap_provenance,
                                0.90,
                                "R-1 SROA DI",
                                di_name,
                            );
                        }
                    }
                }

                // Global values → global_provenance
                if (opcode == c.LLVMStore) {
                    const stored = c.LLVMGetOperand(inst, 0);
                    if (@intFromPtr(stored) != 0 and
                        @intFromPtr(c.LLVMIsAGlobalValue(stored)) != 0)
                    {
                        try srt.recordResolution(
                            @intFromPtr(inst),
                            .global_provenance,
                            0.95,
                            "R-1 global",
                            "store of global value",
                        );
                    }
                }
            }
        }
    }
}

/// Classify an allocation call by its callee name.
/// Uses endsWith (not contains) to avoid false matches.
pub fn classifyAllocationCall(call_inst: c.LLVMValueRef) ?Provenance {
    const callee = getCalleeName(call_inst) orelse return null;
    // Verify the call returns a pointer type
    const ret_ty = c.LLVMTypeOf(call_inst);
    if (@intFromPtr(ret_ty) != 0 and
        c.LLVMGetTypeKind(ret_ty) != c.LLVMPointerTypeKind) return null;
    for (ALLOC_CALLS) |entry| {
        if (std.mem.endsWith(u8, callee, entry.suffix)) return .heap;
    }
    return null;
}

/// Classify an alloca by its DI metadata type name.
fn classifyAllocaDI(alloca: c.LLVMValueRef) ?Provenance {
    const di_name = findAllocaDITypeName(alloca) orelse return null;
    for (HEAP_DI_PREFIXES) |prefix| {
        if (std.mem.startsWith(u8, di_name, prefix)) return .heap;
    }
    return null;
}

/// Find the DI type name for an alloca instruction.
/// Walks through llvm.dbg.declare / llvm.dbg.addr intrinsics.
fn findAllocaDITypeName(alloca: c.LLVMValueRef) ?[]const u8 {
    // Check if this is actually an alloca
    if (c.LLVMGetInstructionOpcode(alloca) != c.LLVMAlloca) return null;

    // Search for dbg.declare or dbg.addr pointing to this alloca
    const func = c.LLVMGetInstructionParent(alloca);
    if (@intFromPtr(func) == 0) return null;
    const bb_parent = c.LLVMGetBasicBlockParent(func);
    if (@intFromPtr(bb_parent) == 0) return null;

    var bb = c.LLVMGetFirstBasicBlock(bb_parent);
    while (@intFromPtr(bb) != 0) : (bb = c.LLVMGetNextBasicBlock(bb)) {
        var inst = c.LLVMGetFirstInstruction(bb);
        while (@intFromPtr(inst) != 0) : (inst = c.LLVMGetNextInstruction(inst)) {
            if (!llvm_safe.isCallOrInvoke(c.LLVMGetInstructionOpcode(inst))) continue;
            const callee = getCalleeName(inst) orelse continue;
            if (!std.mem.eql(u8, callee, "llvm.dbg.declare") and
                !std.mem.eql(u8, callee, "llvm.dbg.addr")) continue;

            // The first operand of dbg.declare is a metadata tuple
            // containing (value, DILocalVariable, DIExpression)
            // We check if value matches our alloca
            const num_ops = c.LLVMGetNumOperands(inst);
            if (num_ops < 1) continue;
            // The metadata operand is the last one
            const md = c.LLVMGetOperand(inst, @as(c_uint, @intCast(num_ops - 1)));
            if (@intFromPtr(md) == 0) continue;

            // Try to extract the variable from the metadata
            const di_var = extractDIVariableFromMetadata(md, alloca);
            if (@intFromPtr(di_var) == 0) continue;

            // Get the type from the DILocalVariable
            const di_type = getDITypeFromVariable(di_var);
            if (@intFromPtr(di_type) == 0) continue;

            return getDITypeName(di_type);
        }
    }
    return null;
}

/// Extract DILocalVariable from metadata node, verifying it references
/// the given alloca value.
fn extractDIVariableFromMetadata(md: c.LLVMValueRef, alloca: c.LLVMValueRef) c.LLVMValueRef {
    // The metadata is a tuple: (value, DILocalVariable, DIExpression)
    const num_ops = c.LLVMGetNumOperands(md);
    if (num_ops < 3) return @ptrFromInt(0);

    // First operand should be the value (our alloca)
    const val = c.LLVMGetOperand(md, 0);
    if (val != alloca) return @ptrFromInt(0);

    // Second operand is the DILocalVariable
    return c.LLVMGetOperand(md, 1);
}

/// Get the DI type from a DILocalVariable node.
fn getDITypeFromVariable(di_var: c.LLVMValueRef) c.LLVMValueRef {
    const num_ops = c.LLVMGetNumOperands(di_var);
    var i: c_uint = 0;
    while (i < num_ops) : (i += 1) {
        const op = c.LLVMGetOperand(di_var, i);
        if (@intFromPtr(op) == 0) continue;
        // DIType nodes have a tag — check if this looks like a type
        const name = c.LLVMGetValueName(op);
        if (@intFromPtr(name) != 0) return op;
    }
    return @ptrFromInt(0);
}

/// Get the name string from a DIType node.
fn getDITypeName(di_type: c.LLVMValueRef) ?[]const u8 {
    const name_ptr = c.LLVMGetValueName(di_type);
    if (@intFromPtr(name_ptr) == 0) return null;
    const name = std.mem.sliceTo(name_ptr, 0);
    if (name.len == 0) return null;
    return name;
}

/// Get callee name from a call instruction.
pub fn getCalleeName(inst: c.LLVMValueRef) ?[]const u8 {
    const called_val = c.LLVMGetCalledValue(inst);
    if (@intFromPtr(called_val) == 0) return null;
    const name_raw = c.LLVMGetValueName(called_val);
    if (@intFromPtr(name_raw) == 0) return null;
    const name = std.mem.sliceTo(name_raw, 0);
    if (name.len == 0) return null;
    return name;
}

/// Trace the provenance of a value through the def-use chain.
/// Used by downstream passes for on-demand provenance queries.
pub fn traceProvenance(
    srt: *const SemanticTree,
    value: c.LLVMValueRef,
    depth: u32,
) Provenance {
    if (depth > MAX_TRACE_DEPTH) return .unknown;

    const ref = @intFromPtr(value);

    // Check SRT for already-known provenance
    if (srt.hasKind(ref, .heap_provenance) != null) return .heap;
    if (srt.hasKind(ref, .global_provenance) != null) return .global;

    // Not an instruction — check type
    if (@intFromPtr(c.LLVMIsAInstruction(value)) == 0) {
        // Global value
        if (@intFromPtr(c.LLVMIsAGlobalValue(value)) != 0) {
            if (c.LLVMIsGlobalConstant(value) != 0) return .global;
            return .heap; // Mutable global — treat as heap
        }
        // Function argument — check SRT
        if (@intFromPtr(c.LLVMIsAArgument(value)) != 0) {
            if (srt.hasKind(ref, .heap_provenance) != null) return .heap;
            return .unknown;
        }
        return .unknown;
    }

    const opcode = c.LLVMGetInstructionOpcode(value);

    return switch (opcode) {
        c.LLVMAlloca => classifyAllocaDI(value) orelse .stack,
        c.LLVMCall, c.LLVMInvoke => classifyAllocationCall(value) orelse .unknown,

        // Propagation: doesn't change provenance
        c.LLVMGetElementPtr => traceProvenance(srt, c.LLVMGetOperand(value, 0), depth + 1),
        c.LLVMBitCast => traceProvenance(srt, c.LLVMGetOperand(value, 0), depth + 1),
        c.LLVMAddrSpaceCast => traceProvenance(srt, c.LLVMGetOperand(value, 0), depth + 1),
        c.LLVMIntToPtr => .unknown,

        // PHI: merge provenance from all incoming values
        c.LLVMPHI => {
            var prov: Provenance = .unknown;
            var i: c_uint = 0;
            while (i < c.LLVMCountIncoming(value)) : (i += 1) {
                const incoming = c.LLVMGetIncomingValue(value, i);
                const incoming_prov = traceProvenance(srt, incoming, depth + 1);
                prov = mergeProvenance(prov, incoming_prov);
            }
            return prov;
        },

        // Select: merge true and false provenance
        c.LLVMSelect => {
            const t = traceProvenance(srt, c.LLVMGetOperand(value, 1), depth + 1);
            const f = traceProvenance(srt, c.LLVMGetOperand(value, 2), depth + 1);
            return mergeProvenance(t, f);
        },

        // Load: from heap container → still heap
        c.LLVMLoad => {
            const src_prov = traceProvenance(srt, c.LLVMGetOperand(value, 0), depth + 1);
            return if (src_prov == .heap) .heap else src_prov;
        },

        // Global value instruction
        c.LLVMGlobalValue => .global,

        else => .unknown,
    };
}

/// Merge two provenance results. If they disagree, return unknown (conservative).
fn mergeProvenance(a: Provenance, b: Provenance) Provenance {
    if (a == b) return a;
    if (a == .unknown) return b;
    if (b == .unknown) return a;
    return .unknown; // heap + stack mixed → unknown
}
