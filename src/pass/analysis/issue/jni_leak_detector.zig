//! JNI Leak Detector Pass
//!
//! Detects JNI-specific resource leak patterns that are commonly missed by
//! generic FFI analysis. Implements three detection rules:
//!
//!   Rule J1: Local Reference Leak — New*/Find*/GetObject* without DeleteLocalRef
//!   Rule J2: Array Elements Leak  — Get*ArrayElements without Release*ArrayElements
//!   Rule J3: String Leak          — GetString*Chars without ReleaseString*Chars
//!
//! These rules target the 5 false-negative patterns identified in the JNI bug
//! corpus where the baseline recall is only 37.5% (3/8 bugs detected).

const std = @import("std");
const c = @import("../../../ir/llvm_raw.zig").c;
const llvm_safe = @import("../../../ir/llvm_safe.zig");

const PassContext = @import("../../pass.zig").PassContext;
const PassKind = @import("../../pass.zig").PassKind;
const DiagnosticWriter = @import("../../pass.zig").DiagnosticWriter;

const Location = @import("../../../diag/issue.zig").Location;
const Issue = @import("../../../diag/issue.zig").Issue;
const IssueKind = @import("../../../diag/issue.zig").IssueKind;
const Severity = @import("../../../diag/issue.zig").Severity;

// ============================================================================
// JNI Function Classification Tables
// ============================================================================

/// Classification of a JNI function's resource management role.
const JniRole = enum {
    /// Acquires a local reference (needs DeleteLocalRef or return)
    local_ref_acquire,
    /// Acquires a global reference (needs DeleteGlobalRef)
    global_ref_acquire,
    /// Borrows array elements pointer (needs Release*ArrayElements)
    array_borrow,
    /// Borrows string chars pointer (needs ReleaseString*Chars)
    string_borrow,
    /// Releases a local reference
    local_ref_release,
    /// Releases a global reference
    global_ref_release,
    /// Releases array elements
    array_release,
    /// Releases string chars
    string_release,
    /// Not a tracked JNI function
    none,
};

/// A single entry in the JNI function classification table.
const JniFuncEntry = struct {
    /// Substring to match in function name (suffix match).
    pattern: []const u8,
    /// Resource management role of this function.
    role: JniRole,
};

/// Authoritative classification table for JNI functions.
/// Covers all acquire/release pairs mentioned in the JNI specification.
const JNI_FUNC_TABLE = [_]JniFuncEntry{
    // ── Local Ref Acquire (need DeleteLocalRef) ──
    .{ .pattern = "NewStringUTF", .role = .local_ref_acquire },
    .{ .pattern = "NewString", .role = .local_ref_acquire },
    .{ .pattern = "NewByteArray", .role = .local_ref_acquire },
    .{ .pattern = "NewShortArray", .role = .local_ref_acquire },
    .{ .pattern = "NewIntArray", .role = .local_ref_acquire },
    .{ .pattern = "NewLongArray", .role = .local_ref_acquire },
    .{ .pattern = "NewFloatArray", .role = .local_ref_acquire },
    .{ .pattern = "NewDoubleArray", .role = .local_ref_acquire },
    .{ .pattern = "NewBooleanArray", .role = .local_ref_acquire },
    .{ .pattern = "NewCharArray", .role = .local_ref_acquire },
    .{ .pattern = "NewObject", .role = .local_ref_acquire },
    .{ .pattern = "NewObjectArray", .role = .local_ref_acquire },
    .{ .pattern = "FindClass", .role = .local_ref_acquire },
    .{ .pattern = "GetObjectClass", .role = .local_ref_acquire },
    .{ .pattern = "GetSuperclass", .role = .local_ref_acquire },
    .{ .pattern = "CallObjectMethod", .role = .local_ref_acquire },
    .{ .pattern = "CallStaticObjectMethod", .role = .local_ref_acquire },
    .{ .pattern = "CallNonvirtualObjectMethod", .role = .local_ref_acquire },
    .{ .pattern = "GetObjectArrayElement", .role = .local_ref_acquire },
    .{ .pattern = "GetObjectField", .role = .local_ref_acquire },
    .{ .pattern = "GetStaticObjectField", .role = .local_ref_acquire },
    .{ .pattern = "NewDirectByteBuffer", .role = .local_ref_acquire },
    .{ .pattern = "NewWeakGlobalRef", .role = .local_ref_acquire },

    // ── Global Ref Acquire (need DeleteGlobalRef) ──
    .{ .pattern = "NewGlobalRef", .role = .global_ref_acquire },

    // ── Local Ref Create (auto-freed on return, but track for loop safety) ──
    .{ .pattern = "NewLocalRef", .role = .local_ref_acquire },

    // ── Array Borrow (need Release*ArrayElements) ──
    .{ .pattern = "GetByteArrayElements", .role = .array_borrow },
    .{ .pattern = "GetCharArrayElements", .role = .array_borrow },
    .{ .pattern = "GetShortArrayElements", .role = .array_borrow },
    .{ .pattern = "GetIntArrayElements", .role = .array_borrow },
    .{ .pattern = "GetLongArrayElements", .role = .array_borrow },
    .{ .pattern = "GetFloatArrayElements", .role = .array_borrow },
    .{ .pattern = "GetDoubleArrayElements", .role = .array_borrow },
    .{ .pattern = "GetBooleanArrayElements", .role = .array_borrow },
    .{ .pattern = "GetPrimitiveArrayCritical", .role = .array_borrow },

    // ── String Borrow (need ReleaseString*Chars) ──
    .{ .pattern = "GetStringUTFChars", .role = .string_borrow },
    .{ .pattern = "GetStringChars", .role = .string_borrow },
    .{ .pattern = "GetStringUTF", .role = .string_borrow },
    .{ .pattern = "GetCriticalString", .role = .string_borrow },
    .{ .pattern = "GetStringUTFLength", .role = .none }, // no-op query
    .{ .pattern = "GetStringLength", .role = .none }, // no-op query

    // ── Releases ──
    .{ .pattern = "DeleteLocalRef", .role = .local_ref_release },
    .{ .pattern = "DeleteGlobalRef", .role = .global_ref_release },
    .{ .pattern = "ReleaseByteArrayElements", .role = .array_release },
    .{ .pattern = "ReleaseCharArrayElements", .role = .array_release },
    .{ .pattern = "ReleaseShortArrayElements", .role = .array_release },
    .{ .pattern = "ReleaseIntArrayElements", .role = .array_release },
    .{ .pattern = "ReleaseLongArrayElements", .role = .array_release },
    .{ .pattern = "ReleaseFloatArrayElements", .role = .array_release },
    .{ .pattern = "ReleaseDoubleArrayElements", .role = .array_release },
    .{ .pattern = "ReleaseBooleanArrayElements", .role = .array_release },
    .{ .pattern = "ReleasePrimitiveArrayCritical", .role = .array_release },
    .{ .pattern = "ReleaseStringUTFChars", .role = .string_release },
    .{ .pattern = "ReleaseStringChars", .role = .string_release },
};

// ============================================================================
// Per-function tracking state
// ============================================================================

/// Tracked acquire operation within a single function.
const AcquiredRef = struct {
    /// The call instruction that acquired the resource.
    inst: c.LLVMValueRef,
    /// The JNI function name (e.g., "NewStringUTF").
    func_name: []const u8,
    /// Role classification of the acquire operation.
    role: JniRole,
};

/// Per-function analysis state for JNI leak tracking.
const JniFunctionState = struct {
    allocator: std.mem.Allocator,
    /// All acquired refs not yet matched with a release.
    acquired_refs: std.ArrayList(AcquiredRef),
    /// Count of local ref releases observed.
    local_releases: u32 = 0,
    /// Count of global ref releases observed.
    global_releases: u32 = 0,
    /// Count of array releases observed.
    array_releases: u32 = 0,
    /// Count of string releases observed.
    string_releases: u32 = 0,

    fn init(allocator: std.mem.Allocator) error{OutOfMemory}!JniFunctionState {
        return .{
            .allocator = allocator,
            .acquired_refs = try std.ArrayList(AcquiredRef).initCapacity(allocator, 0),
        };
    }

    fn deinit(self: *JniFunctionState) void {
        self.acquired_refs.deinit(self.allocator);
    }

    /// Record an acquire operation.
    fn addAcquire(self: *JniFunctionState, inst: c.LLVMValueRef, func_name: []const u8, role: JniRole) !void {
        try self.acquired_refs.append(self.allocator, .{
            .inst = inst,
            .func_name = func_name,
            .role = role,
        });
    }

    /// Record a release operation and try to match it with an acquire.
    fn addRelease(self: *JniFunctionState, role: JniRole) void {
        switch (role) {
            .local_ref_release => self.local_releases += 1,
            .global_ref_release => self.global_releases += 1,
            .array_release => self.array_releases += 1,
            .string_release => self.string_releases += 1,
            else => {},
        }

        // Try to match with an acquire of compatible type.
        // Simple strategy: remove one acquire of matching category.
        var best_idx: ?usize = null;
        for (self.acquired_refs.items, 0..) |ref, i| {
            if (isCompatibleRole(ref.role, role)) {
                best_idx = i;
                break; // match first compatible
            }
        }
        if (best_idx) |idx| {
            _ = self.acquired_refs.swapRemove(idx);
        }
    }

    /// Get remaining unmatched acquires (the leaks).
    fn getLeaks(self: *const JniFunctionState) []const AcquiredRef {
        return self.acquired_refs.items;
    }
};

/// Check if an acquire role is compatible with a release role.
fn isCompatibleRole(acquire: JniRole, release: JniRole) bool {
    return switch (release) {
        .local_ref_release => acquire == .local_ref_acquire,
        .global_ref_release => acquire == .global_ref_acquire,
        .array_release => acquire == .array_borrow,
        .string_release => acquire == .string_borrow,
        else => false,
    };
}

// ============================================================================
// Classifier
// ============================================================================

/// Classify a JNI function name into its resource management role.
fn classifyJniFunc(name: []const u8) JniRole {
    for (JNI_FUNC_TABLE) |entry| {
        if (std.mem.indexOf(u8, name, entry.pattern) != null) {
            return entry.role;
        }
    }
    return .none;
}

/// Check if any function name looks like a JNI function (for early filtering).
fn isJniFunction(name: []const u8) bool {
    // Fast check: must contain common JNI prefixes/suffixes
    const jni_indicators = [_][]const u8{
        "NewString",   "NewByteArray", "NewIntArray",     "NewGlobalRef",
        "DeleteLocal", "DeleteGlobal", "FindClass",       "GetStringUTF",
        "GetStringCh", "GetByteArray", "GetIntArray",     "ReleaseByte",
        "ReleaseStr",  "GetObjectArr", "CallObjectMetho", "AttachCurrent",
        "DetachCurr",  "NewObject",    "NewLocalRef",
    };
    for (jni_indicators) |ind| {
        if (std.mem.indexOf(u8, name, ind) != null) return true;
    }
    return false;
}

// ============================================================================
// Main Pass
// ============================================================================

pub const JniLeakDetectorPass = struct {
    pub const name = "jni-leak-detector";
    pub const kind = PassKind.analysis;
    pub const deps = &[_][]const u8{"ffi-boundary"};

    /// Run the JNI leak detector pass.
    pub fn run(ctx: *PassContext, diag: *DiagnosticWriter) !void {
        if (ctx.module == null) return;

        const module = ctx.module.?.raw;

        _ = ctx.data_flow_graph.getFFIBoundaries(); // available for future scope filtering

        var total_issues: usize = 0;
        var jni_functions_found: usize = 0;

        // Iterate over all non-declaration functions in the module
        var func = c.LLVMGetFirstFunction(module);
        while (@intFromPtr(func) != 0) : (func = c.LLVMGetNextFunction(func)) {
            if (c.LLVMIsDeclaration(func) != 0) continue;

            const found = analyzeFunction(ctx, func, diag) catch |err| {
                const func_name_raw = c.LLVMGetValueName(func);
                const func_name = if (func_name_raw != null) std.mem.span(func_name_raw) else "unknown";
                diag.warn("JniLeakDetector: skipped function '{s}' due to error: {}", .{ func_name, err });
                ctx.recordDegradedFunction();
                continue;
            };
            if (found > 0) jni_functions_found += 1;
            total_issues += found;
        }

        if (total_issues > 0) {
            diag.info("JniLeakDetector: {d} JNI leak issues found across {d} functions", .{ total_issues, jni_functions_found });
        } else {
            diag.debug("JniLeakDetector: no JNI leaks detected", .{});
        }
    }

    /// Analyze a single function for JNI leak patterns.
    ///
    /// Scans all instructions for JNI calls, classifies each as acquire/release,
    /// then reports any unmatched acquires as leaks.
    fn analyzeFunction(ctx: *PassContext, func: c.LLVMValueRef, _: *DiagnosticWriter) !usize {
        var state = try JniFunctionState.init(ctx.allocator);
        defer state.deinit();

        const func_name_ptr = c.LLVMGetValueName(func);
        const func_name = if (@intFromPtr(func_name_ptr) != 0)
            std.mem.span(func_name_ptr)
        else
            "unknown";

        const location = Location.init(func_name);

        // Scan all basic blocks
        var bb = c.LLVMGetFirstBasicBlock(func);
        while (@intFromPtr(bb) != 0) : (bb = c.LLVMGetNextBasicBlock(bb)) {
            var inst = c.LLVMGetFirstInstruction(bb);
            while (@intFromPtr(inst) != 0) : (inst = c.LLVMGetNextInstruction(inst)) {
                const opcode = c.LLVMGetInstructionOpcode(inst);
                if (!llvm_safe.isCallOrInvoke(opcode)) continue;

                const called_name = getCalleeName(inst) orelse continue;

                // Quick filter: skip non-JNI functions entirely
                if (!isJniFunction(called_name)) continue;

                const role = classifyJniFunc(called_name);
                switch (role) {
                    .local_ref_acquire, .global_ref_acquire, .array_borrow, .string_borrow => {
                        try state.addAcquire(inst, called_name, role);
                    },
                    .local_ref_release, .global_ref_release, .array_release, .string_release => {
                        state.addRelease(role);
                    },
                    .none => {},
                }
            }
        }

        // Report unmatched acquires as leaks
        const leaks = state.getLeaks();
        var issue_count: usize = 0;
        for (leaks) |leak| {
            try reportLeak(ctx, &leak, func_name, location);
            issue_count += 1;
        }

        return issue_count;
    }

    /// Report a single JNI leak as an issue.
    fn reportLeak(
        ctx: *PassContext,
        leak: *const AcquiredRef,
        caller_func: []const u8,
        location: Location,
    ) !void {
        const leak_type = switch (leak.role) {
            .local_ref_acquire => "JNI Local Reference Leak",
            .global_ref_acquire => "JNI Global Reference Leak",
            .array_borrow => "JNI Array Elements Leak",
            .string_borrow => "JNI String Leak",
            else => "JNI Resource Leak",
        };

        const release_hint = switch (leak.role) {
            .local_ref_acquire => "DeleteLocalRef()",
            .global_ref_acquire => "DeleteGlobalRef()",
            .array_borrow => "Release*ArrayElements()",
            .string_borrow => "ReleaseString*Chars()",
            else => "appropriate release function",
        };

        const message = try std.fmt.allocPrint(
            ctx.allocator,
            "[OMI-JNI-LEAK] {s}: {s}() called without matching {s} in {s}",
            .{ leak_type, leak.func_name, release_hint, caller_func },
        );
        defer ctx.allocator.free(message);

        // Map to appropriate IssueKind and severity
        const issue_kind: IssueKind = switch (leak.role) {
            .global_ref_acquire => .cross_language_leak, // Global ref leaks are always real leaks
            .local_ref_acquire => .cross_language_leak, // Local ref leaks in loops are real leaks
            .array_borrow => .memory_leak, // Native memory pinning leak
            .string_borrow => .memory_leak, // Native memory pinning leak
            else => .memory_leak,
        };

        const severity: Severity = switch (leak.role) {
            .global_ref_acquire => .critical, // Global ref leaks persist forever
            .array_borrow => .high, // Pins GC, can cause OOM
            .string_borrow => .high, // Pins GC, can cause OOM
            .local_ref_acquire => .medium, // Auto-freed on return, but dangerous in loops
            else => .medium,
        };

        var issue = Issue.init(issue_kind, message, location, severity, 0.85);
        issue.owned = true;
        try ctx.addIssue(&issue);
    }

    /// Get callee name from a call instruction.
    fn getCalleeName(inst: c.LLVMValueRef) ?[]const u8 {
        const num_operands = @as(c_uint, @bitCast(c.LLVMGetNumOperands(inst)));
        if (num_operands == 0) return null;

        const called_value = c.LLVMGetOperand(inst, num_operands - 1);
        if (@intFromPtr(called_value) == 0) return null;

        const name_raw = c.LLVMGetValueName(called_value);
        if (@intFromPtr(name_raw) == 0) return null;

        const raw_name = std.mem.sliceTo(name_raw, 0);
        if (raw_name.len == 0) return null;

        // Strip leading control characters (LLVM naming artifact)
        const clean_name = if (raw_name.len > 0 and raw_name[0] < 32) raw_name[1..] else raw_name;
        if (clean_name.len == 0) return null;

        return clean_name;
    }
};

// ============================================================================
// Tests
// ============================================================================

test "JniLeakDetectorPass - pass structure" {
    try std.testing.expectEqual(@as([]const u8, "jni-leak-detector"), JniLeakDetectorPass.name);
    try std.testing.expectEqual(PassKind.analysis, JniLeakDetectorPass.kind);
    try std.testing.expectEqual(@as(usize, 1), JniLeakDetectorPass.deps.len);
}

test "JniLeakDetectorPass - JNI function classification" {
    // Local ref acquire
    try std.testing.expectEqual(JniRole.local_ref_acquire, classifyJniFunc("NewStringUTF"));
    try std.testing.expectEqual(JniRole.local_ref_acquire, classifyJniFunc("NewByteArray"));
    try std.testing.expectEqual(JniRole.local_ref_acquire, classifyJniFunc("FindClass"));
    try std.testing.expectEqual(JniRole.local_ref_acquire, classifyJniFunc("GetObjectArrayElement"));
    try std.testing.expectEqual(JniRole.local_ref_acquire, classifyJniFunc("CallObjectMethod"));

    // Global ref acquire
    try std.testing.expectEqual(JniRole.global_ref_acquire, classifyJniFunc("NewGlobalRef"));

    // Array borrow
    try std.testing.expectEqual(JniRole.array_borrow, classifyJniFunc("GetByteArrayElements"));
    try std.testing.expectEqual(JniRole.array_borrow, classifyJniFunc("GetIntArrayElements"));

    // String borrow
    try std.testing.expectEqual(JniRole.string_borrow, classifyJniFunc("GetStringUTFChars"));
    try std.testing.expectEqual(JniRole.string_borrow, classifyJniFunc("GetStringChars"));

    // Releases
    try std.testing.expectEqual(JniRole.local_ref_release, classifyJniFunc("DeleteLocalRef"));
    try std.testing.expectEqual(JniRole.global_ref_release, classifyJniFunc("DeleteGlobalRef"));
    try std.testing.expectEqual(JniRole.array_release, classifyJniFunc("ReleaseByteArrayElements"));
    try std.testing.expectEqual(JniRole.string_release, classifyJniFunc("ReleaseStringUTFChars"));

    // Non-JNI
    try std.testing.expectEqual(JniRole.none, classifyJniFunc("malloc"));
    try std.testing.expectEqual(JniRole.none, classifyJniFunc("printf"));
    try std.testing.expectEqual(JniRole.none, classifyJniFunc("free"));
}

test "JniLeakDetectorPass - isJniFunction filter" {
    try std.testing.expect(isJniFunction("NewStringUTF"));
    try std.testing.expect(isJniFunction("GetByteArrayElements"));
    try std.testing.expect(isJniFunction("DeleteGlobalRef"));
    try std.testing.expect(!isJniFunction("malloc"));
    try std.testing.expect(!isJniFunction("printf"));
    try std.testing.expect(!isJniFunction("my_regular_function"));
}

test "JniLeakDetectorPass - role compatibility" {
    try std.testing.expect(isCompatibleRole(.local_ref_acquire, .local_ref_release));
    try std.testing.expect(!isCompatibleRole(.local_ref_acquire, .global_ref_release));
    try std.testing.expect(isCompatibleRole(.global_ref_acquire, .global_ref_release));
    try std.testing.expect(isCompatibleRole(.array_borrow, .array_release));
    try std.testing.expect(isCompatibleRole(.string_borrow, .string_release));
    try std.testing.expect(!isCompatibleRole(.array_borrow, .string_release));
}

test "JniLeakDetectorPass - JniFunctionState acquire/release matching" {
    var state = JniFunctionState.init(std.testing.allocator);
    defer state.deinit();

    // Add two local ref acquires
    const mock_inst: c.LLVMValueRef = @ptrFromInt(0x1000);
    try state.addAcquire(mock_inst, "NewStringUTF", .local_ref_acquire);
    try state.addAcquire(mock_inst, "FindClass", .local_ref_acquire);

    // One release should match one acquire
    state.addRelease(.local_ref_release);
    try std.testing.expectEqual(@as(usize, 1), state.getLeaks().len);

    // Second release should clear the other
    state.addRelease(.local_ref_release);
    try std.testing.expectEqual(@as(usize, 0), state.getLeaks().len);
}

test "JniLeakDetectorPass - JniFunctionState mismatched release" {
    var state = JniFunctionState.init(std.testing.allocator);
    defer state.deinit();

    const mock_inst: c.LLVMValueRef = @ptrFromInt(0x1000);
    try state.addAcquire(mock_inst, "NewStringUTF", .local_ref_acquire);

    // Global ref release should NOT match local ref acquire
    state.addRelease(.global_ref_release);
    try std.testing.expectEqual(@as(usize, 1), state.getLeaks().len);
}
