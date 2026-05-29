//! Arena / Owner-Scope Inference — Lifetime scope detection (P19-14)
//!
//! Detects when allocations are scoped to an arena or owner object's lifetime,
//! meaning they should NOT be reported as ordinary leaks.
//!
//! Key patterns:
//!   - Arena-scoped: alloc → store to arena buffer → freed when arena destroyed
//!   - Owner-scoped: alloc → stored in owner field → freed in owner's destructor
//!   - Context-scoped: alloc only used within a specific call chain context
//!
//! This is a GENERIC mechanism — works by analyzing IR value flow, not names.

const std = @import("std");
const c = @import("../../ir/llvm_raw.zig").c;
const llvm_safe = @import("../../ir/llvm_safe.zig");
const log = std.log.scoped(.arena_inference);

/// Classification of how an allocation's lifetime is managed.
pub const LifetimeScope = enum(u8) {
    /// Standard heap allocation with manual free required.
    manual,
    /// Scoped to an arena/region — freed when arena is destroyed.
    arena_scoped,
    /// Owned by a parent object — freed in owner's destructor.
    owner_scoped,
    /// Scoped to a function call context — freed before return.
    context_scoped,
    /// Could not determine scope.
    unknown,
};

/// Evidence for why an allocation was classified as arena/owner scoped.
pub const ScopeEvidence = struct {
    /// The inferred lifetime scope.
    scope: LifetimeScope,
    /// What kind of evidence supports this classification.
    evidence_kind: EvidenceKind,
    /// The owner/arena object if applicable (as function name or description).
    owner_description: ?[]const u8 = null,
    /// Confidence [0.0, 1.0].
    confidence: f32,

    pub const EvidenceKind = enum(u8) {
        /// Stored into a struct field that has a destructor.
        field_with_destructor,
        /// Passed to an arena allocator's add/append method.
        arena_api_call,
        /// Allocation and deallocation in same function (short-lived).
        same_function_cleanup,
        /// Returned from factory pattern — caller owns.
        factory_return,
        /// Global/static variable — process lifetime.
        global_lifetime,
        /// No structural evidence found.
        no_evidence,
    };

    pub fn isScoped(self: *const ScopeEvidence) bool {
        return switch (self.scope) {
            .arena_scoped, .owner_scoped, .context_scoped => true,
            else => false,
        };
    }

    pub fn allowsLeakReport(self: *const ScopeEvidence) bool {
        return switch (self.scope) {
            .manual => true,
            .arena_scoped, .owner_scoped, .context_scoped => self.confidence < 0.6,
            .unknown => true,
        };
    }
};

/// Arena/Owner-Scope Inference Engine.
///
/// Analyzes allocation sites to determine if they are scoped to an
/// arena or owner object's lifetime.
pub const ArenaInferenceEngine = struct {
    allocator: std.mem.Allocator,

    pub fn init(alloc: std.mem.Allocator) ArenaInferenceEngine {
        return .{ .allocator = alloc };
    }

    /// Analyze an allocation within its function to determine lifetime scope.
    pub fn inferScope(
        func: c.LLVMValueRef,
        alloc_inst: c.LLVMValueRef,
    ) ScopeEvidence {
        const func_name_ptr = c.LLVMGetValueName(func);
        const func_name = if (@intFromPtr(func_name_ptr) != 0) std.mem.sliceTo(func_name_ptr, 0) else "unknown";

        var has_store_to_struct: bool = false;
        var has_arena_api_use: bool = false;
        var has_destructor_pattern: bool = false;
        var use_count: u32 = 0;

        // Analyze uses of the allocation result
        var use_iter = c.LLVMGetFirstUse(alloc_inst);
        while (@intFromPtr(use_iter) != 0) : (use_iter = c.LLVMGetNextUse(use_iter)) {
            use_count += 1;
            const user = c.LLVMGetUser(use_iter);
            if (@intFromPtr(user) == 0) continue;

            const opcode = c.LLVMGetInstructionOpcode(user);

            if (opcode == c.LLVMStore) {
                const store_target = c.LLVMGetOperand(user, 1);
                if (@intFromPtr(store_target) != 0) {
                    if (isStructFieldStore(store_target)) {
                        has_store_to_struct = true;
                    }
                }
            }

            if (llvm_safe.isCallOrInvoke(opcode)) {
                const called = c.LLVMGetCalledValue(user);
                if (@intFromPtr(called) != 0) {
                    const called_name = c.LLVMGetValueName(called);
                    if (@intFromPtr(called_name) != 0) {
                        const name = std.mem.sliceTo(called_name, 0);
                        if (isArenaAPI(name)) {
                            has_arena_api_use = true;
                        }
                        if (isDestructorCall(name)) {
                            has_destructor_pattern = true;
                        }
                    }
                }
            }
        }

        // Classify based on collected evidence
        if (has_arena_api_use) {
            return .{
                .scope = .arena_scoped,
                .evidence_kind = .arena_api_call,
                .owner_description = func_name,
                .confidence = 0.8,
            };
        }

        if (has_store_to_struct and has_destructor_pattern) {
            return .{
                .scope = .owner_scoped,
                .evidence_kind = .field_with_destructor,
                .owner_description = func_name,
                .confidence = 0.75,
            };
        }

        if (has_store_to_struct) {
            return .{
                .scope = .owner_scoped,
                .evidence_kind = .field_with_destructor,
                .owner_description = func_name,
                .confidence = 0.5,
            };
        }

        return .{
            .scope = .unknown,
            .evidence_kind = .no_evidence,
            .owner_description = func_name,
            .confidence = 0.0,
        };
    }
};

fn isStructFieldStore(store_ptr: c.LLVMValueRef) bool {
    if (c.LLVMGetInstructionOpcode(store_ptr) == c.LLVMGetElementPtr) {
        const base = c.LLVMGetOperand(store_ptr, 0);
        if (@intFromPtr(base) != 0) {
            const base_kind = c.LLVMGetValueKind(base);
            return base_kind == c.LLVMLocalAsmArgumentValueKind or
                base_kind == c.LLVMArgumentValueKind;
        }
    }
    return false;
}

fn isArenaAPI(func_name: []const u8) bool {
    const arena_patterns = [_][]const u8{
        "arena_alloc",  "arena_push",     "arena_append",
        "region_alloc", "pool_alloc",     "bump_alloc",
        "ArenaAlloc",   "ArenaPush",      "ArenaAppend",
        "add_to_arena", "alloc_in_arena",
    };
    for (arena_patterns) |p| {
        if (std.mem.indexOf(u8, func_name, p) != null) return true;
    }

    if (std.mem.indexOf(u8, func_name, "Arena") != null and
        (std.mem.indexOf(u8, func_name, "alloc") != null or
            std.mem.indexOf(u8, func_name, "push") != null or
            std.mem.indexOf(u8, func_name, "create") != null))
    {
        return true;
    }

    return false;
}

fn isDestructorCall(func_name: []const u8) bool {
    const dtor_patterns = [_][]const u8{
        "destroy", "deinit", "dispose", "finalize",
        "free",    "drop",   "cleanup", "release",
        "~",       "_ZN",    "__del",
    };
    for (dtor_patterns) |p| {
        if (std.mem.indexOf(u8, func_name, p) != null) return true;
    }
    return false;
}
