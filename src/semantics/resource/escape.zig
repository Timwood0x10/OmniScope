//! EscapeKind — How does a resource pointer escape the current scope?
//!
//! When a pointer "escapes", it means the pointer's lifetime extends beyond
//! the current function scope. Escaped pointers are NOT leaks — they've
//! been handed off to someone else who becomes responsible for cleanup.
//!
//! Every escape has a kind that determines:
//!   1. Whether it counts as a valid disposal of ownership
//!   2. Who is now responsible for freeing the resource
//!   3. What confidence we have in the escape being legitimate

const std = @import("std");

const contract_mod = @import("contract.zig");
pub const PointerContract = contract_mod.PointerContract;

// ============================================================================
// EscapeKind — Where did this pointer go?
// ============================================================================

/// Classification of how a resource pointer escapes the allocating function's scope.
pub const EscapeKind = enum(u8) {
    /// Returned directly to caller as return value.
    /// Caller now owns the resource. Valid disposal of ownership.
    return_to_caller,

    /// Written to an out-parameter (**T or *T output param).
    /// Caller of THIS function receives ownership through the out-param.
    /// Valid disposal of ownership.
    out_param,

    /// Stored into a field of an owner object (e.g., obj->data = ptr).
    /// The owner object's destructor will eventually free it.
    /// Valid disposal IF the owner object itself is properly managed.
    field_store,

    /// Stored into a global or static variable.
    /// Lives until process exit. NOT a leak (process-lifetime).
    /// But may indicate missing cleanup on shutdown path.
    global_store,

    /// Same as global_store but specifically for C++ static initializers
    /// or __attribute__((constructor)) functions.
    static_lifetime,

    /// Passed to a callback/closure/function-pointer argument.
    /// The callback may use the pointer after this function returns.
    /// Lifetime risk — callback must not outlive the resource.
    callback,

    /// Passed to a thread-spawning API (pthread_create, std::thread, etc.).
    /// The new thread may access the pointer after spawn returns.
    /// Lifetime risk — must ensure proper synchronization.
    thread,

    /// Stored into a container (vector push_back, list insert, dict setitem).
    /// Container takes ownership. Valid if container is managed.
    container,

    /// Consumed by a known consumer function (cJSON_Delete, xmlFreeDoc, etc.).
    /// Consumer takes full responsibility for freeing.
    consumed_by_function,

    /// Escape kind could not be determined.
    unknown,

    /// No escape — pointer is still local to this function.
    no_escape,

    pub fn isValidDisposal(kind: EscapeKind) bool {
        return switch (kind) {
            .return_to_caller, .out_param, .field_store, .global_store, .static_lifetime, .consumed_by_function, .container => true,
            .callback, .thread => false,
            .unknown, .no_escape => false,
        };
    }

    pub fn isLifetimeRisk(kind: EscapeKind) bool {
        return switch (kind) {
            .callback, .thread => true,
            else => false,
        };
    }

    pub fn isProcessLifetime(kind: EscapeKind) bool {
        return kind == .global_store or kind == .static_lifetime;
    }

    pub fn name(kind: EscapeKind) []const u8 {
        return switch (kind) {
            .return_to_caller => "return_to_caller",
            .out_param => "out_param",
            .field_store => "field_store",
            .global_store => "global_store",
            .static_lifetime => "static_lifetime",
            .callback => "callback",
            .thread => "thread",
            .container => "container",
            .consumed_by_function => "consumed_by_function",
            .unknown => "unknown",
            .no_escape => "no_escape",
        };
    }
};

// ============================================================================
// EscapeRecord — Single escape event for a resource instance
// ============================================================================

/// Records one way in which a specific resource pointer escaped.
/// Each AllocNode may have multiple EscapeRecords (a pointer can escape
/// in multiple ways before being fully disposed).
pub const EscapeRecord = struct {
    /// What kind of escape this is.
    kind: EscapeKind,
    /// Instruction address where the escape occurred (0 = unknown).
    inst_addr: u64,
    /// Basic block ID where escape occurred (0 = unknown).
    bb_id: u32,
    /// Target of the escape (function name for callback, variable name for store, etc.).
    target_name: ?[]const u8 = null,
    /// Confidence [0.0, 1.0] that this is a real (not spurious) escape.
    confidence: f32 = 0.7,
    /// Which effect triggered this escape classification.
    source_effect: ?[]const u8 = null,

    pub fn init(kind: EscapeKind, inst_addr: u64) EscapeRecord {
        return .{
            .kind = kind,
            .inst_addr = inst_addr,
            .bb_id = 0,
        };
    }

    pub fn withTarget(self: *EscapeRecord, name: []const u8) void {
        self.target_name = name;
    }

    pub fn withConfidence(self: *EscapeRecord, conf: f32) void {
        self.confidence = conf;
    }

    pub fn withSourceEffect(self: *EscapeRecord, effect: []const u8) void {
        self.source_effect = effect;
    }
};

// ============================================================================
// EscapeList — Collection of escapes for one resource instance
// ============================================================================

/// All recorded escape events for a single resource (allocation site).
/// Used to determine whether a resource has been properly disposed of.
pub const EscapeList = struct {
    escapes: std.ArrayList(EscapeRecord),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) EscapeList {
        return .{
            .escapes = std.ArrayList(EscapeRecord).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *EscapeList) void {
        self.escapes.deinit();
    }

    /// Record a new escape event.
    pub fn add(self: *EscapeList, record: EscapeRecord) !void {
        try self.escapes.append(record);
    }

    /// Check if there exists ANY valid-disposal escape.
    pub fn hasValidEscape(self: *const EscapeList) bool {
        for (self.escapes.items) |esc| {
            if (esc.kind.isValidDisposal()) return true;
        }
        return false;
    }

    /// Check if there exists ANY lifetime-risk escape (callback/thread).
    pub fn hasLifetimeRisk(self: *const EscapeList) bool {
        for (self.escapes.items) |esc| {
            if (esc.kind.isLifetimeRisk()) return true;
        }
        return false;
    }

    /// Count total escapes recorded.
    pub fn count(self: *const EscapeList) usize {
        return self.escapes.items.len;
    }

    /// Iterate over all escapes.
    pub fn iterate(self: *const EscapeList, context: anytype, comptime visitor_fn: fn (context: @TypeOf(context), esc: *const EscapeRecord) bool) void {
        for (self.escapes.items) |*esc| {
            if (!visitor_fn(context, esc)) break;
        }
    }
};

// ============================================================================
// EscapeClassifier — Classify IR operations as escape kinds
// ============================================================================

/// Classifies LLVM IR instructions as potential escape events.
/// Called during memory graph construction when tracking pointer flows.
pub const EscapeClassifier = struct {
    /// Known callback-registering functions whose pointer argument escapes.
    const callback_patterns = [_][]const u8{
        "pthread_create",           "thrd_create",
        "register_atexit",          "atexit",
        "signal",                   "sigaction",
        "SDL_AddTimer",             "SDL_SetEventFilter",
        "glfwSetKeyCallback",       "glfwSetCursorPosCallback",
        "RegisterClass",            "SetWindowLongPtrW",
        "objc_setAssociatedObject",
    };

    /// Known thread-spawning functions.
    const thread_patterns = [_][]const u8{
        "pthread_create", "thrd_create",
        "std::thread",    "_ZNSt6thread",
        "CreateThread",   "_beginthreadex",
        "std::async",     "std::spawn",
        "Task::spawn",    "tokio::spawn",
        "go_cgo_invoke", // Go cgo
    };

    /// Known container-insertion functions.
    const container_patterns = [_][]const u8{
        "push_back",           "emplace_back",
        "insert",              "emplace",
        "add",                 "append",
        "PyList_SetItem",      "PyDict_SetItem",
        "PyTuple_SetItem",     "PySet_Add",
        "g_hash_table_insert", "g_ptr_array_add",
        "json_object_set_new", "cJSON_AddItemToArray",
        "vector_push",         "array_append",
    };

    /// Classify a callee + context as an escape kind.
    /// Returns null if the call is NOT an escape (normal usage).
    pub fn classifyCall(callee_name: []const u8, arg_index: u8) ?EscapeKind {
        _ = arg_index;
        // Check callback patterns first (highest risk)
        for (callback_patterns) |pattern| {
            if (nameMatches(callee_name, pattern)) {
                return .callback;
            }
        }

        // Thread patterns
        for (thread_patterns) |pattern| {
            if (nameMatches(callee_name, pattern)) {
                return .thread;
            }
        }

        // Container patterns
        for (container_patterns) |pattern| {
            if (nameMatches(callee_name, pattern)) {
                return .container;
            }
        }

        return null;
    }

    /// Simple case-insensitive substring match for escape pattern detection.
    fn nameMatches(callee: []const u8, pattern: []const u8) bool {
        if (pattern.len > callee.len) return false;
        var i: usize = 0;
        while (i <= callee.len - pattern.len) : (i += 1) {
            var matched = true;
            for (pattern, 0..) |pc, j| {
                const cc = callee[i + j];
                const pc_lower = if (pc >= 'A' and pc <= 'Z') pc + 32 else pc;
                const cc_lower = if (cc >= 'A' and cc <= 'Z') cc + 32 else cc;
                if (cc_lower != pc_lower) {
                    matched = false;
                    break;
                }
            }
            if (matched) return true;
        }
        return false;
    }
};
