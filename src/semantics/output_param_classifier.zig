//! Output Parameter Classifier module.
//!
//! Identifies C API output parameters that are commonly misinterpreted
//! as borrow/escape issues by ptr_lifetime analysis.
//!
//! Two detection strategies:
//!   1. Function-level: Known C API families that use output params (sqlite3_*, getsockopt, etc.)
//!   2. Parameter-level: Name-based heuristics (pp*, out*, result*, ret*)

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

/// Known C API function families that use output parameters.
/// Format: function prefix → index of the output parameter (0-based).
const OutputParamFunctionFamily = struct {
    prefix: []const u8,
    output_param_index: u32,
    description: []const u8,
};

const known_output_param_families = [_]OutputParamFunctionFamily{
    .{ .prefix = "sqlite3_prepare", .output_param_index = 4, .description = "sqlite3 prepare stmt" },
    .{ .prefix = "sqlite3_open", .output_param_index = 1, .description = "sqlite3 open db" },
    .{ .prefix = "sqlite3_bind_", .output_param_index = 0xFFFF, .description = "sqlite3 bind (no output)" },
    .{ .prefix = "getsockopt", .output_param_index = 4, .description = "getsockopt optval" },
    .{ .prefix = "getaddrinfo", .output_param_index = 3, .description = "getaddrinfo result" },
    .{ .prefix = "getnameinfo", .output_param_index = 4, .description = "getnameinfo host" },
    .{ .prefix = "pthread_create", .output_param_index = 0, .description = "pthread thread id" },
    .{ .prefix = "pthread_join", .output_param_index = 1, .description = "pthread retval" },
    .{ .prefix = "sem_getvalue", .output_param_index = 1, .description = "semaphore value" },
    .{ .prefix = "clock_gettime", .output_param_index = 1, .description = "clock timespec" },
    .{ .prefix = "gettimeofday", .output_param_index = 0, .description = "timeval" },
    .{ .prefix = "stat", .output_param_index = 1, .description = "stat buf" },
    .{ .prefix = "fstat", .output_param_index = 1, .description = "fstat buf" },
    .{ .prefix = "lstat", .output_param_index = 1, .description = "lstat buf" },
    .{ .prefix = "pipe", .output_param_index = 0, .description = "pipe fd array" },
    .{ .prefix = "socketpair", .output_param_index = 3, .description = "socketpair sv" },
    .{ .prefix = "accept", .output_param_index = 1, .description = "accept addr" },
    .{ .prefix = "recvfrom", .output_param_index = 4, .description = "recvfrom src_addr" },
    .{ .prefix = "recvmsg", .output_param_index = 1, .description = "recvmsg msg" },
    .{ .prefix = "msgrcv", .output_param_index = 1, .description = "msgrcv msgp" },
    .{ .prefix = "shmat", .output_param_index = 0xFFFF, .description = "shmat returns ptr" },
    .{ .prefix = "JNI_CreateJavaVM", .output_param_index = 0, .description = "JNI vm ptr" },
    .{ .prefix = "regcomp", .output_param_index = 1, .description = "regex compiled" },
    .{ .prefix = "ldap_search_s", .output_param_index = 4, .description = "ldap result" },
    .{ .prefix = "curl_easy_getinfo", .output_param_index = 2, .description = "curl info ptr" },
    .{ .prefix = "avcodec_open2", .output_param_index = 0, .description = "avcodec context" },
    .{ .prefix = "avcodec_decode", .output_param_index = 2, .description = "avcodec frame" },
    .{ .prefix = "json_parse", .output_param_index = 1, .description = "json parse result" },
    .{ .prefix = "xmlParseChunk", .output_param_index = 0, .description = "xml parser ctx" },
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
    /// Uses conservative patterns to minimize false positives.
    pub fn isOutputParamName(name: []const u8) bool {
        // Windows API style: ppFoo, xppFoo (pointer-to-pointer)
        if (std.mem.startsWith(u8, name, "pp") or std.mem.startsWith(u8, name, "xpp")) return true;

        // Explicit output suffixes
        if (std.mem.endsWith(u8, name, "_out") or std.mem.endsWith(u8, name, "_out_")) return true;
        if (std.mem.endsWith(u8, name, "_result") or std.mem.endsWith(u8, name, "_retval")) return true;

        // Common output param names (exact match or prefix)
        const exact_output_names = [_][]const u8{
            "result", "output", "out",    "retval",   "ret",
            "ppStmt", "ppDb",   "ppData", "ppResult",
        };
        for (exact_output_names) |known| {
            if (std.mem.eql(u8, name, known)) return true;
        }

        return false;
    }

    /// Classifies a function to detect if it uses output parameters.
    /// Uses both function-level knowledge base and parameter-level heuristics.
    pub fn classifyFunction(
        _: *OutputParamClassifier,
        func_name: []const u8,
        param_names: []const []const u8,
    ) ClassificationResult {
        // Strategy 1: Check known C API families
        for (known_output_param_families) |family| {
            if (std.mem.startsWith(u8, func_name, family.prefix)) {
                if (family.output_param_index != 0xFFFF) {
                    return ClassificationResult{
                        .has_output_params = true,
                        .is_c_api_pattern = true,
                        .confidence = 95,
                    };
                }
            }
        }

        // Strategy 2: Check parameter names for output patterns
        var has_output = false;
        for (param_names) |pname| {
            if (isOutputParamName(pname)) {
                has_output = true;
                break;
            }
        }

        // Strategy 3: Function name heuristic — int-returning functions with
        // "get"/"query"/"fetch" prefix often use output params
        if (!has_output) {
            const output_heuristic_prefixes = [_][]const u8{
                "get_",  "query_", "fetch_",  "read_",    "recv_",
                "load_", "parse_", "decode_", "extract_",
            };
            for (output_heuristic_prefixes) |prefix| {
                if (std.mem.startsWith(u8, func_name, prefix)) {
                    // Only apply if function has >= 2 params (common for output param APIs)
                    if (param_names.len >= 2) {
                        return ClassificationResult{
                            .has_output_params = true,
                            .is_c_api_pattern = true,
                            .confidence = 50, // Lower confidence for heuristic
                        };
                    }
                }
            }
        }

        return ClassificationResult{
            .has_output_params = has_output,
            .is_c_api_pattern = has_output,
            .confidence = if (has_output) @as(u8, 75) else @as(u8, 0),
        };
    }

    /// Quick check: does this function likely use output parameters?
    /// Used by ptr_lifetime to suppress false-positive return-value warnings.
    pub fn isLikelyOutputParamFunction(func_name: []const u8) bool {
        // Check known families first (high confidence)
        for (known_output_param_families) |family| {
            if (std.mem.startsWith(u8, func_name, family.prefix)) {
                if (family.output_param_index != 0xFFFF) return true;
            }
        }

        // Check function name patterns that strongly suggest output params
        const strong_patterns = [_][]const u8{
            "sqlite3_prepare",  "sqlite3_open",   "sqlite3_bind",
            "getsockopt",       "setsockopt",     "getaddrinfo",
            "getnameinfo",      "pthread_create", "pthread_join",
            "clock_gettime",    "clock_getres",   "gettimeofday",
            "regcomp",          "regexec",        "curl_easy_getinfo",
            "curl_easy_setopt", "avcodec_",       "avformat_",
            "avparser_",        "json_",          "xmlParse",
            "ldap_",
        };
        for (strong_patterns) |pat| {
            if (std.mem.indexOf(u8, func_name, pat) != null) return true;
        }

        return false;
    }

    /// Checks if a function has output parameters (simple name-based check).
    pub fn hasOutputParams(func_name: []const u8, param_names: []const []const u8) bool {
        _ = func_name;
        for (param_names) |pname| {
            if (isOutputParamName(pname)) return true;
        }
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
    try std.testing.expect(result.confidence >= 90);
}

test "output_param_classifier - getsockopt_pattern" {
    var classifier = try OutputParamClassifier.init();
    defer classifier.deinit();

    const result = classifier.classifyFunction(
        "getsockopt",
        &.{"optval"},
    );

    try std.testing.expect(result.has_output_params);
    try std.testing.expect(result.is_c_api_pattern);
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
    try std.testing.expect(OutputParamClassifier.isOutputParamName("ppData"));
    try std.testing.expect(OutputParamClassifier.isOutputParamName("xppBuffer"));
    try std.testing.expect(OutputParamClassifier.isOutputParamName("ret"));
}

test "output_param_classifier - input_param_naming" {
    // "out" as substring of "without" should NOT match (we use endsWith now)
    try std.testing.expect(!OutputParamClassifier.isOutputParamName("without"));
    try std.testing.expect(!OutputParamClassifier.isOutputParamName("input_data"));
    try std.testing.expect(!OutputParamClassifier.isOutputParamName("source"));
    try std.testing.expect(!OutputParamClassifier.isOutputParamName("buffer"));
}

test "output_param_classifier - isLikelyOutputParamFunction" {
    try std.testing.expect(OutputParamClassifier.isLikelyOutputParamFunction("sqlite3_prepare_v2"));
    try std.testing.expect(OutputParamClassifier.isLikelyOutputParamFunction("getsockopt"));
    try std.testing.expect(OutputParamClassifier.isLikelyOutputParamFunction("pthread_create"));
    try std.testing.expect(!OutputParamClassifier.isLikelyOutputParamFunction("malloc"));
    try std.testing.expect(!OutputParamClassifier.isLikelyOutputParamFunction("free"));
    try std.testing.expect(!OutputParamClassifier.isLikelyOutputParamFunction("process_data"));
}

test "output_param_classifier - function_level_heuristic" {
    var classifier = try OutputParamClassifier.init();
    defer classifier.deinit();

    // get_ prefix with >= 2 params should be detected
    const result = classifier.classifyFunction(
        "get_user_info",
        &.{ "user_id", "info_out" },
    );
    try std.testing.expect(result.has_output_params);
}
