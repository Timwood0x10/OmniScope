//! Output Parameter Classifier module.
//!
//! This standalone module identifies C API output parameters that are commonly
//! misinterpreted as borrow/escape issues.
//!
//! Key Selling Points:
//!   - Standalone module, no dependencies
//!   - Detects output parameter patterns from function signatures
//!   - Integration-ready with ptr_lifetime.zig

const std = @import("std");

/// Role of a parameter in a function call.
pub const ParamRole = enum(u8) {
    input,
    output,
    input_output,
    unknown,
};

/// Information about a classified parameter.
pub const ParamInfo = struct {
    index: u32,
    role: ParamRole,
    confidence: u8,
};

/// Result of classifying a function's output parameters.
pub const ClassificationResult = struct {
    has_output_params: bool,
    is_c_api_pattern: bool,
    confidence: u8,
};

/// Output Parameter Classifier.
pub const OutputParamClassifier = struct {
    /// Arena allocator for long-lived data.
    arena: std.heap.ArenaAllocator,

    /// Initializes a new classifier.
    pub fn init() anyerror!OutputParamClassifier {
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        errdefer arena.deinit();

        return OutputParamClassifier{
            .arena = arena,
        };
    }

    /// Deinitializes the classifier.
    pub fn deinit(classifier: *OutputParamClassifier) void {
        classifier.arena.deinit();
        classifier.* = undefined;
    }

    /// Checks if a parameter name suggests output parameter.
    pub fn isOutputParamName(name: []const u8) bool {
        if (std.mem.containsAtLeast(u8, name, 1, "out")) return true;
        if (std.mem.containsAtLeast(u8, name, 1, "result")) return true;
        if (std.mem.startsWith(u8, name, "pp")) return true;
        if (std.mem.startsWith(u8, name, "xpp")) return true;
        if (std.mem.startsWith(u8, name, "ret")) return true;
        return false;
    }

    /// Classifies a function to detect if it uses output parameters.
    pub fn classifyFunction(
        _: *OutputParamClassifier,
        func_name: []const u8,
        param_names: []const []const u8,
    ) ClassificationResult {
        _ = func_name;

        var has_output = false;
        for (param_names) |pname| {
            if (isOutputParamName(pname)) {
                has_output = true;
                break;
            }
        }

        return ClassificationResult{
            .has_output_params = has_output,
            .is_c_api_pattern = has_output,
            .confidence = if (has_output) @as(u8, 80) else @as(u8, 0),
        };
    }

    /// Checks if a function has output parameters (simple name-based check).
    pub fn hasOutputParams(func_name: []const u8, param_names: []const []const u8) bool {
        for (param_names) |pname| {
            if (isOutputParamName(pname)) return true;
        }
        _ = func_name;
        return false;
    }
};

// ============================================================================
// Tests
// ============================================================================

test "output_param_classifier - sqlite3_prepare_pattern" {
    var classifier = try OutputParamClassifier.init();
    defer classifier.deinit();

    const result = classifier.classifyFunction(
        "sqlite3_prepare",
        &.{"ppStmt"},
    );

    try std.testing.expect(result.has_output_params);
    try std.testing.expect(result.is_c_api_pattern);
    try std.testing.expect(result.confidence == 80);
}

test "output_param_classifier - getsockopt_pattern" {
    var classifier = try OutputParamClassifier.init();
    defer classifier.deinit();

    const result = classifier.classifyFunction(
        "getsockopt",
        &.{"optval"},
    );

    try std.testing.expect(!result.has_output_params);
}

test "output_param_classifier - regular_function" {
    var classifier = try OutputParamClassifier.init();
    defer classifier.deinit();

    const result = classifier.classifyFunction(
        "process_data",
        &.{"input"},
    );

    try std.testing.expect(!result.has_output_params);
}

test "output_param_classifier - out_param_naming" {
    try std.testing.expect(OutputParamClassifier.isOutputParamName("data_out"));
    try std.testing.expect(OutputParamClassifier.isOutputParamName("result_ptr"));
    try std.testing.expect(OutputParamClassifier.isOutputParamName("ppData"));
    try std.testing.expect(OutputParamClassifier.isOutputParamName("xppBuffer"));
    try std.testing.expect(OutputParamClassifier.isOutputParamName("ret_val"));
}

test "output_param_classifier - input_param_naming" {
    try std.testing.expect(!OutputParamClassifier.isOutputParamName("input_data"));
    try std.testing.expect(!OutputParamClassifier.isOutputParamName("source"));
    try std.testing.expect(!OutputParamClassifier.isOutputParamName("buffer"));
}
