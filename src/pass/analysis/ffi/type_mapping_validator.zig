//! Type Mapping Validator for FFI Boundaries
//!
//! Validates type compatibility across language boundaries (C, Rust, Go, Java, Zig, Python).
//! Detects width mismatches, sign mismatches, and alignment differences that could cause
//! undefined behavior at FFI boundaries.
//!
//! Key features:
//!   - Type mapping tables between languages (e.g., Rust i32 ↔ C int ↔ Java jint ↔ Go C.int)
//!   - Width mismatch detection (e.g., Rust i32 vs C long on LP64)
//!   - Sign mismatch detection (e.g., Rust u32 vs C int)
//!   - Alignment difference detection (struct padding)
//!   - Pointer and array type compatibility checking
//!   - Platform-specific type width detection (LP64 vs ILP32)
//!   - Integration with existing IssueKind.ffi_type_mismatch reporting
//!
//! Usage:
//!   const validator = TypeMappingValidator.init(allocator);
//!   const issues = validator.validateCrossLanguageTypes(caller_type, callee_type, ...);

const std = @import("std");
const c = @import("../../../ir/llvm_raw.zig").c;
const PassContext = @import("../../pass.zig").PassContext;
const PassKind = @import("../../pass.zig").PassKind;
const DiagnosticWriter = @import("../../pass.zig").DiagnosticWriter;
const Location = @import("../../../diag/issue.zig").Location;
const Issue = @import("../../../diag/issue.zig").Issue;
const IssueKind = @import("../../../diag/issue.zig").IssueKind;
const Severity = @import("../../../diag/issue.zig").Severity;
const TraceEntry = @import("../../../diag/issue.zig").TraceEntry;

// ============================================================================
// Platform Model Detection
// ============================================================================

/// Platform data models for C type sizes.
pub const PlatformModel = enum {
    /// ILP32: int, long, pointer are 32-bit (32-bit platforms)
    ilp32,
    /// LP64: long and pointer are 64-bit, int is 32-bit (Unix/macOS 64-bit)
    lp64,
    /// LLP64: long long and pointer are 64-bit, int and long are 32-bit (Windows 64-bit)
    llp64,
};

/// Detect the current platform model based on pointer size.
///
/// Returns:
///   PlatformModel based on @sizeOf(usize)
pub fn detectPlatformModel() PlatformModel {
    const ptr_size = @sizeOf(usize);
    if (ptr_size == 4) return .ilp32;
    // On most Unix-like systems (macOS, Linux), long == pointer == 64-bit
    return .lp64;
}

/// Get the bit width of a C long for a given platform model.
///
/// Arguments:
///   model - The platform model
///
/// Returns:
///   Bit width of C long
pub fn getCLongWidth(model: PlatformModel) u32 {
    return switch (model) {
        .ilp32 => 32,
        .lp64 => 64,
        .llp64 => 32,
    };
}

/// Get the bit width of a C pointer for a given platform model.
///
/// Arguments:
///   model - The platform model
///
/// Returns:
///   Bit width of C pointer
pub fn getCPointerWidth(model: PlatformModel) u32 {
    return switch (model) {
        .ilp32 => 32,
        .lp64 => 64,
        .llp64 => 64,
    };
}

// ============================================================================
// Type Mapping Tables
// ============================================================================

/// Represents a type in a specific language with its properties.
pub const LanguageType = struct {
    /// Language identifier (e.g., "c", "rust", "go", "java", "zig", "python")
    language: []const u8,
    /// Type name in the language (e.g., "int", "i32", "jint")
    type_name: []const u8,
    /// Size in bits (0 if platform-dependent)
    bit_width: u32,
    /// Whether the type is signed
    is_signed: bool,
    /// Alignment in bytes (0 if platform-dependent)
    alignment: u32,
    /// Whether the type is platform-dependent
    is_platform_dependent: bool,
};

/// Represents a pointer type with its base type and mutability.
pub const PointerType = struct {
    /// The base element type
    element_type: *const LanguageType,
    /// Whether the pointer is mutable
    is_mutable: bool,
    /// Whether it's a raw pointer (C-style) vs typed pointer
    is_raw: bool,
    /// Pointer width in bits (platform-dependent)
    bit_width: u32,
};

/// Represents an array type with its element type and size.
pub const ArrayType = struct {
    /// The element type
    element_type: *const LanguageType,
    /// Number of elements (0 if dynamic/unknown)
    length: u32,
    /// Whether the array is statically sized
    is_static: bool,
};

/// Type mapping entry for cross-language compatibility.
pub const TypeMapping = struct {
    /// Source type
    source: LanguageType,
    /// Target type
    target: LanguageType,
    /// Whether the mapping is safe (no data loss or UB)
    is_safe: bool,
    /// Potential issues with this mapping
    issues: []const []const u8,
};

/// Type mismatch issue detected by the validator.
pub const TypeMismatchIssue = struct {
    kind: TypeMismatchKind,
    source_type: LanguageType,
    target_type: LanguageType,
    description: []const u8,
    severity: Severity,
    confidence: f64,
};

/// Pointer type mismatch issue.
pub const PointerMismatchIssue = struct {
    kind: PointerMismatchKind,
    source: PointerType,
    target: PointerType,
    description: []const u8,
    severity: Severity,
    confidence: f64,
};

/// Array type mismatch issue.
pub const ArrayMismatchIssue = struct {
    kind: ArrayMismatchKind,
    source: ArrayType,
    target: ArrayType,
    description: []const u8,
    severity: Severity,
    confidence: f64,
};

/// Types of type mismatches that can be detected.
pub const TypeMismatchKind = enum(u8) {
    width_mismatch,
    sign_mismatch,
    alignment_mismatch,
    platform_dependent_mismatch,
    unsafe_mapping,
};

/// Types of pointer mismatches.
pub const PointerMismatchKind = enum(u8) {
    mutability_mismatch,
    element_type_mismatch,
    raw_vs_typed_mismatch,
    width_mismatch,
};

/// Types of array mismatches.
pub const ArrayMismatchKind = enum(u8) {
    element_type_mismatch,
    length_mismatch,
    static_vs_dynamic_mismatch,
};

// ============================================================================
// Common Type Definitions
// ============================================================================

/// Common C types with their properties (LP64 model)
pub const c_types = struct {
    pub const int8_t = LanguageType{ .language = "c", .type_name = "int8_t", .bit_width = 8, .is_signed = true, .alignment = 1, .is_platform_dependent = false };
    pub const uint8_t = LanguageType{ .language = "c", .type_name = "uint8_t", .bit_width = 8, .is_signed = false, .alignment = 1, .is_platform_dependent = false };
    pub const int16_t = LanguageType{ .language = "c", .type_name = "int16_t", .bit_width = 16, .is_signed = true, .alignment = 2, .is_platform_dependent = false };
    pub const uint16_t = LanguageType{ .language = "c", .type_name = "uint16_t", .bit_width = 16, .is_signed = false, .alignment = 2, .is_platform_dependent = false };
    pub const int32_t = LanguageType{ .language = "c", .type_name = "int32_t", .bit_width = 32, .is_signed = true, .alignment = 4, .is_platform_dependent = false };
    pub const uint32_t = LanguageType{ .language = "c", .type_name = "uint32_t", .bit_width = 32, .is_signed = false, .alignment = 4, .is_platform_dependent = false };
    pub const int64_t = LanguageType{ .language = "c", .type_name = "int64_t", .bit_width = 64, .is_signed = true, .alignment = 8, .is_platform_dependent = false };
    pub const uint64_t = LanguageType{ .language = "c", .type_name = "uint64_t", .bit_width = 64, .is_signed = false, .alignment = 8, .is_platform_dependent = false };
    pub const int = LanguageType{ .language = "c", .type_name = "int", .bit_width = 32, .is_signed = true, .alignment = 4, .is_platform_dependent = true };
    pub const unsigned_int = LanguageType{ .language = "c", .type_name = "unsigned int", .bit_width = 32, .is_signed = false, .alignment = 4, .is_platform_dependent = true };
    pub const long = LanguageType{ .language = "c", .type_name = "long", .bit_width = 64, .is_signed = true, .alignment = 8, .is_platform_dependent = true };
    pub const unsigned_long = LanguageType{ .language = "c", .type_name = "unsigned long", .bit_width = 64, .is_signed = false, .alignment = 8, .is_platform_dependent = true };
    pub const long_long = LanguageType{ .language = "c", .type_name = "long long", .bit_width = 64, .is_signed = true, .alignment = 8, .is_platform_dependent = true };
    pub const size_t = LanguageType{ .language = "c", .type_name = "size_t", .bit_width = 64, .is_signed = false, .alignment = 8, .is_platform_dependent = true };
    pub const ssize_t = LanguageType{ .language = "c", .type_name = "ssize_t", .bit_width = 64, .is_signed = true, .alignment = 8, .is_platform_dependent = true };
    pub const ptrdiff_t = LanguageType{ .language = "c", .type_name = "ptrdiff_t", .bit_width = 64, .is_signed = true, .alignment = 8, .is_platform_dependent = true };
    pub const intptr_t = LanguageType{ .language = "c", .type_name = "intptr_t", .bit_width = 64, .is_signed = true, .alignment = 8, .is_platform_dependent = true };
    pub const uintptr_t = LanguageType{ .language = "c", .type_name = "uintptr_t", .bit_width = 64, .is_signed = false, .alignment = 8, .is_platform_dependent = true };
};

/// Common Rust types with their properties
pub const rust_types = struct {
    pub const rust_i8 = LanguageType{ .language = "rust", .type_name = "i8", .bit_width = 8, .is_signed = true, .alignment = 1, .is_platform_dependent = false };
    pub const rust_u8 = LanguageType{ .language = "rust", .type_name = "u8", .bit_width = 8, .is_signed = false, .alignment = 1, .is_platform_dependent = false };
    pub const rust_i16 = LanguageType{ .language = "rust", .type_name = "i16", .bit_width = 16, .is_signed = true, .alignment = 2, .is_platform_dependent = false };
    pub const rust_u16 = LanguageType{ .language = "rust", .type_name = "u16", .bit_width = 16, .is_signed = false, .alignment = 2, .is_platform_dependent = false };
    pub const rust_i32 = LanguageType{ .language = "rust", .type_name = "i32", .bit_width = 32, .is_signed = true, .alignment = 4, .is_platform_dependent = false };
    pub const rust_u32 = LanguageType{ .language = "rust", .type_name = "u32", .bit_width = 32, .is_signed = false, .alignment = 4, .is_platform_dependent = false };
    pub const rust_i64 = LanguageType{ .language = "rust", .type_name = "i64", .bit_width = 64, .is_signed = true, .alignment = 8, .is_platform_dependent = false };
    pub const rust_u64 = LanguageType{ .language = "rust", .type_name = "u64", .bit_width = 64, .is_signed = false, .alignment = 8, .is_platform_dependent = false };
    pub const rust_isize = LanguageType{ .language = "rust", .type_name = "isize", .bit_width = 64, .is_signed = true, .alignment = 8, .is_platform_dependent = true };
    pub const rust_usize = LanguageType{ .language = "rust", .type_name = "usize", .bit_width = 64, .is_signed = false, .alignment = 8, .is_platform_dependent = true };
};

/// Common Java types with their properties
pub const java_types = struct {
    pub const jbyte = LanguageType{ .language = "java", .type_name = "jbyte", .bit_width = 8, .is_signed = true, .alignment = 1, .is_platform_dependent = false };
    pub const jchar = LanguageType{ .language = "java", .type_name = "jchar", .bit_width = 16, .is_signed = false, .alignment = 2, .is_platform_dependent = false };
    pub const jshort = LanguageType{ .language = "java", .type_name = "jshort", .bit_width = 16, .is_signed = true, .alignment = 2, .is_platform_dependent = false };
    pub const jint = LanguageType{ .language = "java", .type_name = "jint", .bit_width = 32, .is_signed = true, .alignment = 4, .is_platform_dependent = false };
    pub const jlong = LanguageType{ .language = "java", .type_name = "jlong", .bit_width = 64, .is_signed = true, .alignment = 8, .is_platform_dependent = false };
    pub const jfloat = LanguageType{ .language = "java", .type_name = "jfloat", .bit_width = 32, .is_signed = true, .alignment = 4, .is_platform_dependent = false };
    pub const jdouble = LanguageType{ .language = "java", .type_name = "jdouble", .bit_width = 64, .is_signed = true, .alignment = 8, .is_platform_dependent = false };
};

/// Common Go types with their properties
pub const go_types = struct {
    pub const C_int = LanguageType{ .language = "go", .type_name = "C.int", .bit_width = 32, .is_signed = true, .alignment = 4, .is_platform_dependent = true };
    pub const C_uint = LanguageType{ .language = "go", .type_name = "C.uint", .bit_width = 32, .is_signed = false, .alignment = 4, .is_platform_dependent = true };
    pub const C_long = LanguageType{ .language = "go", .type_name = "C.long", .bit_width = 64, .is_signed = true, .alignment = 8, .is_platform_dependent = true };
    pub const C_ulong = LanguageType{ .language = "go", .type_name = "C.ulong", .bit_width = 64, .is_signed = false, .alignment = 8, .is_platform_dependent = true };
    pub const C_longlong = LanguageType{ .language = "go", .type_name = "C.longlong", .bit_width = 64, .is_signed = true, .alignment = 8, .is_platform_dependent = true };
    pub const C_size_t = LanguageType{ .language = "go", .type_name = "C.size_t", .bit_width = 64, .is_signed = false, .alignment = 8, .is_platform_dependent = true };
};

/// Common Zig types with their properties
pub const zig_types = struct {
    pub const zig_i8 = LanguageType{ .language = "zig", .type_name = "i8", .bit_width = 8, .is_signed = true, .alignment = 1, .is_platform_dependent = false };
    pub const zig_u8 = LanguageType{ .language = "zig", .type_name = "u8", .bit_width = 8, .is_signed = false, .alignment = 1, .is_platform_dependent = false };
    pub const zig_i16 = LanguageType{ .language = "zig", .type_name = "i16", .bit_width = 16, .is_signed = true, .alignment = 2, .is_platform_dependent = false };
    pub const zig_u16 = LanguageType{ .language = "zig", .type_name = "u16", .bit_width = 16, .is_signed = false, .alignment = 2, .is_platform_dependent = false };
    pub const zig_i32 = LanguageType{ .language = "zig", .type_name = "i32", .bit_width = 32, .is_signed = true, .alignment = 4, .is_platform_dependent = false };
    pub const zig_u32 = LanguageType{ .language = "zig", .type_name = "u32", .bit_width = 32, .is_signed = false, .alignment = 4, .is_platform_dependent = false };
    pub const zig_i64 = LanguageType{ .language = "zig", .type_name = "i64", .bit_width = 64, .is_signed = true, .alignment = 8, .is_platform_dependent = false };
    pub const zig_u64 = LanguageType{ .language = "zig", .type_name = "u64", .bit_width = 64, .is_signed = false, .alignment = 8, .is_platform_dependent = false };
    pub const zig_isize = LanguageType{ .language = "zig", .type_name = "isize", .bit_width = 64, .is_signed = true, .alignment = 8, .is_platform_dependent = true };
    pub const zig_usize = LanguageType{ .language = "zig", .type_name = "usize", .bit_width = 64, .is_signed = false, .alignment = 8, .is_platform_dependent = true };
};

/// Common Python ctypes types with their properties
pub const python_types = struct {
    pub const py_c_byte = LanguageType{ .language = "python", .type_name = "c_byte", .bit_width = 8, .is_signed = true, .alignment = 1, .is_platform_dependent = false };
    pub const py_c_ubyte = LanguageType{ .language = "python", .type_name = "c_ubyte", .bit_width = 8, .is_signed = false, .alignment = 1, .is_platform_dependent = false };
    pub const py_c_short = LanguageType{ .language = "python", .type_name = "c_short", .bit_width = 16, .is_signed = true, .alignment = 2, .is_platform_dependent = false };
    pub const py_c_ushort = LanguageType{ .language = "python", .type_name = "c_ushort", .bit_width = 16, .is_signed = false, .alignment = 2, .is_platform_dependent = false };
    pub const py_c_int = LanguageType{ .language = "python", .type_name = "c_int", .bit_width = 32, .is_signed = true, .alignment = 4, .is_platform_dependent = false };
    pub const py_c_uint = LanguageType{ .language = "python", .type_name = "c_uint", .bit_width = 32, .is_signed = false, .alignment = 4, .is_platform_dependent = false };
    pub const py_c_long = LanguageType{ .language = "python", .type_name = "c_long", .bit_width = 64, .is_signed = true, .alignment = 8, .is_platform_dependent = true };
    pub const py_c_ulong = LanguageType{ .language = "python", .type_name = "c_ulong", .bit_width = 64, .is_signed = false, .alignment = 8, .is_platform_dependent = true };
    pub const py_c_longlong = LanguageType{ .language = "python", .type_name = "c_longlong", .bit_width = 64, .is_signed = true, .alignment = 8, .is_platform_dependent = false };
    pub const py_c_ulonglong = LanguageType{ .language = "python", .type_name = "c_ulonglong", .bit_width = 64, .is_signed = false, .alignment = 8, .is_platform_dependent = false };
    pub const py_c_size_t = LanguageType{ .language = "python", .type_name = "c_size_t", .bit_width = 64, .is_signed = false, .alignment = 8, .is_platform_dependent = true };
    pub const py_c_ssize_t = LanguageType{ .language = "python", .type_name = "c_ssize_t", .bit_width = 64, .is_signed = true, .alignment = 8, .is_platform_dependent = true };
    pub const py_c_void_p = LanguageType{ .language = "python", .type_name = "c_void_p", .bit_width = 64, .is_signed = false, .alignment = 8, .is_platform_dependent = true };
    pub const py_c_char_p = LanguageType{ .language = "python", .type_name = "c_char_p", .bit_width = 64, .is_signed = false, .alignment = 8, .is_platform_dependent = true };
};

// ============================================================================
// Type Mapping Validator
// ============================================================================

/// Main type mapping validator for cross-language FFI boundaries.
pub const TypeMappingValidator = struct {
    allocator: std.mem.Allocator,
    platform_model: PlatformModel,

    /// Initialize the validator with the given allocator.
    pub fn init(allocator: std.mem.Allocator) TypeMappingValidator {
        return .{
            .allocator = allocator,
            .platform_model = detectPlatformModel(),
        };
    }

    /// Initialize the validator with a specific platform model.
    pub fn initWithPlatform(allocator: std.mem.Allocator, model: PlatformModel) TypeMappingValidator {
        return .{
            .allocator = allocator,
            .platform_model = model,
        };
    }

    /// Validate type compatibility between two language types.
    pub fn validateCrossLanguageTypes(
        self: *TypeMappingValidator,
        source: LanguageType,
        target: LanguageType,
        location: Location,
        diag: *DiagnosticWriter,
    ) ![]TypeMismatchIssue {
        var issues = std.ArrayList(TypeMismatchIssue).init(self.allocator);
        errdefer issues.deinit();

        if (self.checkWidthMismatch(source, target)) |issue| {
            try issues.append(issue);
            try self.reportIssue(issue, location, diag);
        }
        if (self.checkSignMismatch(source, target)) |issue| {
            try issues.append(issue);
            try self.reportIssue(issue, location, diag);
        }
        if (self.checkAlignmentMismatch(source, target)) |issue| {
            try issues.append(issue);
            try self.reportIssue(issue, location, diag);
        }
        if (self.checkPlatformDependentMismatch(source, target)) |issue| {
            try issues.append(issue);
            try self.reportIssue(issue, location, diag);
        }
        if (self.checkUnsafeMapping(source, target)) |issue| {
            try issues.append(issue);
            try self.reportIssue(issue, location, diag);
        }

        return issues.toOwnedSlice();
    }

    /// Validate pointer type compatibility between two pointer types.
    pub fn validatePointerType(
        self: *TypeMappingValidator,
        source: PointerType,
        target: PointerType,
        location: Location,
        diag: *DiagnosticWriter,
    ) ![]PointerMismatchIssue {
        var issues = std.ArrayList(PointerMismatchIssue).init(self.allocator);
        errdefer issues.deinit();

        if (source.is_mutable != target.is_mutable) {
            const desc: []const u8 = if (source.is_mutable and !target.is_mutable)
                "Const-correctness violation: mutable pointer passed to const pointer parameter"
            else
                "Unsafe cast: const pointer to mutable pointer";
            const sev: Severity = if (source.is_mutable and !target.is_mutable) .low else .high;
            const issue = PointerMismatchIssue{ .kind = .mutability_mismatch, .source = source, .target = target, .description = desc, .severity = sev, .confidence = 0.9 };
            try issues.append(issue);
            try self.reportPointerIssue(issue, location, diag);
        }
        if (!areTypesCompatible(source.element_type.*, target.element_type.*)) {
            const issue = PointerMismatchIssue{ .kind = .element_type_mismatch, .source = source, .target = target, .description = "Pointer element type mismatch: base types are not compatible", .severity = .high, .confidence = 0.85 };
            try issues.append(issue);
            try self.reportPointerIssue(issue, location, diag);
        }
        if (source.is_raw != target.is_raw) {
            const desc: []const u8 = if (source.is_raw) "Raw pointer to typed pointer conversion loses type safety" else "Typed pointer to raw pointer conversion bypasses type checking";
            const issue = PointerMismatchIssue{ .kind = .raw_vs_typed_mismatch, .source = source, .target = target, .description = desc, .severity = .medium, .confidence = 0.7 };
            try issues.append(issue);
            try self.reportPointerIssue(issue, location, diag);
        }
        return issues.toOwnedSlice();
    }

    /// Validate array type compatibility between two array types.
    pub fn validateArrayType(
        self: *TypeMappingValidator,
        source: ArrayType,
        target: ArrayType,
        location: Location,
        diag: *DiagnosticWriter,
    ) ![]ArrayMismatchIssue {
        var issues = std.ArrayList(ArrayMismatchIssue).init(self.allocator);
        errdefer issues.deinit();

        if (!areTypesCompatible(source.element_type.*, target.element_type.*)) {
            const issue = ArrayMismatchIssue{ .kind = .element_type_mismatch, .source = source, .target = target, .description = "Array element type mismatch: base types are not compatible", .severity = .high, .confidence = 0.85 };
            try issues.append(issue);
            try self.reportArrayIssue(issue, location, diag);
        }
        if (source.is_static and target.is_static and source.length != target.length) {
            const issue = ArrayMismatchIssue{ .kind = .length_mismatch, .source = source, .target = target, .description = std.fmt.allocPrint(self.allocator, "Array length mismatch: source has {d} elements, target expects {d}", .{ source.length, target.length }) catch "Array length mismatch", .severity = .high, .confidence = 0.95 };
            try issues.append(issue);
            try self.reportArrayIssue(issue, location, diag);
        }
        if (source.is_static != target.is_static) {
            const desc: []const u8 = if (source.is_static and !target.is_static) "Static array to dynamic array conversion may lose size information" else "Dynamic array to static array conversion assumes specific size";
            const issue = ArrayMismatchIssue{ .kind = .static_vs_dynamic_mismatch, .source = source, .target = target, .description = desc, .severity = .medium, .confidence = 0.7 };
            try issues.append(issue);
            try self.reportArrayIssue(issue, location, diag);
        }
        return issues.toOwnedSlice();
    }

    fn checkWidthMismatch(self: *TypeMappingValidator, source: LanguageType, target: LanguageType) ?TypeMismatchIssue {
        if (source.bit_width == 0 or target.bit_width == 0) return null;
        if (source.bit_width == target.bit_width) return null;

        const severity: Severity = if (source.bit_width > target.bit_width) .high else .medium;
        const description = std.fmt.allocPrint(
            self.allocator,
            "Width mismatch: {s} ({d} bits) vs {s} ({d} bits)",
            .{ source.type_name, source.bit_width, target.type_name, target.bit_width },
        ) catch "Width mismatch";

        return TypeMismatchIssue{
            .kind = .width_mismatch,
            .source_type = source,
            .target_type = target,
            .description = description,
            .severity = severity,
            .confidence = 0.8,
        };
    }

    fn checkSignMismatch(self: *TypeMappingValidator, source: LanguageType, target: LanguageType) ?TypeMismatchIssue {
        if (source.bit_width != target.bit_width) return null;
        if (source.is_signed == target.is_signed) return null;

        const description = std.fmt.allocPrint(
            self.allocator,
            "Sign mismatch: {s} ({s}) vs {s} ({s})",
            .{
                source.type_name,
                if (source.is_signed) "signed" else "unsigned",
                target.type_name,
                if (target.is_signed) "signed" else "unsigned",
            },
        ) catch "Sign mismatch";

        return TypeMismatchIssue{
            .kind = .sign_mismatch,
            .source_type = source,
            .target_type = target,
            .description = description,
            .severity = .medium,
            .confidence = 0.9,
        };
    }

    fn checkAlignmentMismatch(self: *TypeMappingValidator, source: LanguageType, target: LanguageType) ?TypeMismatchIssue {
        if (source.alignment == 0 or target.alignment == 0) return null;
        if (source.alignment == target.alignment) return null;

        const severity: Severity = if (source.alignment < target.alignment) .high else .low;
        const description = std.fmt.allocPrint(
            self.allocator,
            "Alignment mismatch: {s} (alignment {d}) vs {s} (alignment {d})",
            .{ source.type_name, source.alignment, target.type_name, target.alignment },
        ) catch "Alignment mismatch";

        return TypeMismatchIssue{
            .kind = .alignment_mismatch,
            .source_type = source,
            .target_type = target,
            .description = description,
            .severity = severity,
            .confidence = 0.7,
        };
    }

    fn checkPlatformDependentMismatch(self: *TypeMappingValidator, source: LanguageType, target: LanguageType) ?TypeMismatchIssue {
        if (source.is_platform_dependent == target.is_platform_dependent) return null;

        const description = std.fmt.allocPrint(
            self.allocator,
            "Platform-dependent mismatch: {s} ({s}) vs {s} ({s})",
            .{
                source.type_name,
                if (source.is_platform_dependent) "platform-dependent" else "fixed-width",
                target.type_name,
                if (target.is_platform_dependent) "platform-dependent" else "fixed-width",
            },
        ) catch "Platform-dependent mismatch";

        return TypeMismatchIssue{
            .kind = .platform_dependent_mismatch,
            .source_type = source,
            .target_type = target,
            .description = description,
            .severity = .medium,
            .confidence = 0.6,
        };
    }

    fn checkUnsafeMapping(self: *TypeMappingValidator, source: LanguageType, target: LanguageType) ?TypeMismatchIssue {
        // Table of known unsafe mappings: (source_name, target_name, target_min_width, description)
        const unsafe_map = [_]struct { src: []const u8, tgt: []const u8, tgt_min_w: u32, msg: []const u8 }{
            .{ .src = "i32", .tgt = "long", .tgt_min_w = 64, .msg = "Rust i32 to C long (potential data loss on LP64)" },
            .{ .src = "int", .tgt = "jlong", .tgt_min_w = 0, .msg = "C int to Java jlong (width mismatch + platform dependency)" },
            .{ .src = "C.size_t", .tgt = "i32", .tgt_min_w = 0, .msg = "Go C.size_t to Rust i32 (width and sign mismatch)" },
            .{ .src = "C.ulong", .tgt = "i32", .tgt_min_w = 0, .msg = "Go C.ulong to Rust i32 (width and sign mismatch)" },
            .{ .src = "jint", .tgt = "long", .tgt_min_w = 64, .msg = "Java jint to C long (width mismatch, data loss on LP64)" },
            .{ .src = "c_size_t", .tgt = "i32", .tgt_min_w = 0, .msg = "Python c_size_t to Rust i32 (width and sign mismatch)" },
        };
        for (unsafe_map) |entry| {
            if (std.mem.eql(u8, source.type_name, entry.src) and
                std.mem.eql(u8, target.type_name, entry.tgt) and
                (entry.tgt_min_w == 0 or target.bit_width >= entry.tgt_min_w))
            {
                return TypeMismatchIssue{ .kind = .unsafe_mapping, .source_type = source, .target_type = target, .description = entry.msg, .severity = .high, .confidence = 0.9 };
            }
        }
        // Zig usize to Rust i32 (requires language check)
        if (std.mem.eql(u8, source.type_name, "usize") and std.mem.eql(u8, source.language, "zig") and
            std.mem.eql(u8, target.type_name, "i32") and std.mem.eql(u8, target.language, "rust"))
        {
            return TypeMismatchIssue{ .kind = .unsafe_mapping, .source_type = source, .target_type = target, .description = "Zig usize to Rust i32 (width and sign mismatch)", .severity = .high, .confidence = 0.95 };
        }
        return null;
    }

    fn reportIssue(self: *TypeMappingValidator, issue: TypeMismatchIssue, location: Location, diag: *DiagnosticWriter) !void {
        const trace = try self.allocator.alloc(TraceEntry, 2);
        trace[0] = TraceEntry.initOwned(try std.fmt.allocPrint(
            self.allocator,
            "Source type: {s} ({s})",
            .{ issue.source_type.type_name, issue.source_type.language },
        ));
        trace[1] = TraceEntry.initOwned(try std.fmt.allocPrint(
            self.allocator,
            "Target type: {s} ({s})",
            .{ issue.target_type.type_name, issue.target_type.language },
        ));

        var diag_issue = Issue.initWithTrace(
            .ffi_type_mismatch,
            issue.description,
            location,
            issue.severity,
            issue.confidence,
            trace,
        );
        diag_issue.owned = true;

        diag.warn("[TYPE-MAPPING] {s} → {s}: {s}", .{
            issue.source_type.type_name,
            issue.target_type.type_name,
            issue.description,
        });
    }

    fn reportPointerIssue(self: *TypeMappingValidator, issue: PointerMismatchIssue, location: Location, diag: *DiagnosticWriter) !void {
        const trace = try self.allocator.alloc(TraceEntry, 2);
        trace[0] = TraceEntry.initOwned(try std.fmt.allocPrint(
            self.allocator,
            "Source: *{s}{s}",
            .{ if (issue.source.is_mutable) "" else "const ", issue.source.element_type.type_name },
        ));
        trace[1] = TraceEntry.initOwned(try std.fmt.allocPrint(
            self.allocator,
            "Target: *{s}{s}",
            .{ if (issue.target.is_mutable) "" else "const ", issue.target.element_type.type_name },
        ));

        var diag_issue = Issue.initWithTrace(
            .ffi_type_mismatch,
            issue.description,
            location,
            issue.severity,
            issue.confidence,
            trace,
        );
        diag_issue.owned = true;

        diag.warn("[POINTER-MAPPING] {s}", .{issue.description});
    }

    fn reportArrayIssue(self: *TypeMappingValidator, issue: ArrayMismatchIssue, location: Location, diag: *DiagnosticWriter) !void {
        const trace = try self.allocator.alloc(TraceEntry, 2);
        trace[0] = TraceEntry.initOwned(try std.fmt.allocPrint(
            self.allocator,
            "Source: [{d}]{s}",
            .{ issue.source.length, issue.source.element_type.type_name },
        ));
        trace[1] = TraceEntry.initOwned(try std.fmt.allocPrint(
            self.allocator,
            "Target: [{d}]{s}",
            .{ issue.target.length, issue.target.element_type.type_name },
        ));

        var diag_issue = Issue.initWithTrace(
            .ffi_type_mismatch,
            issue.description,
            location,
            issue.severity,
            issue.confidence,
            trace,
        );
        diag_issue.owned = true;

        diag.warn("[ARRAY-MAPPING] {s}", .{issue.description});
    }

    /// Get a type mapping table for common cross-language conversions.
    pub fn getTypeMappingTable() []const TypeMapping {
        return &[_]TypeMapping{
            // Safe mappings
            .{ .source = c_types.int32_t, .target = rust_types.rust_i32, .is_safe = true, .issues = &[_][]const u8{} },
            .{ .source = c_types.uint32_t, .target = rust_types.rust_u32, .is_safe = true, .issues = &[_][]const u8{} },
            .{ .source = c_types.int64_t, .target = rust_types.rust_i64, .is_safe = true, .issues = &[_][]const u8{} },
            .{ .source = c_types.uint64_t, .target = rust_types.rust_u64, .is_safe = true, .issues = &[_][]const u8{} },
            .{ .source = c_types.int32_t, .target = java_types.jint, .is_safe = true, .issues = &[_][]const u8{} },
            .{ .source = c_types.int32_t, .target = zig_types.zig_i32, .is_safe = true, .issues = &[_][]const u8{} },
            .{ .source = c_types.uint32_t, .target = zig_types.zig_u32, .is_safe = true, .issues = &[_][]const u8{} },
            .{ .source = c_types.int64_t, .target = zig_types.zig_i64, .is_safe = true, .issues = &[_][]const u8{} },
            .{ .source = c_types.int32_t, .target = python_types.py_c_int, .is_safe = true, .issues = &[_][]const u8{} },
            // Unsafe mappings
            .{ .source = c_types.long, .target = rust_types.rust_i32, .is_safe = false, .issues = &[_][]const u8{ "width_mismatch", "platform_dependent" } },
            .{ .source = c_types.size_t, .target = rust_types.rust_i32, .is_safe = false, .issues = &[_][]const u8{ "width_mismatch", "sign_mismatch", "platform_dependent" } },
            .{ .source = c_types.int, .target = java_types.jlong, .is_safe = false, .issues = &[_][]const u8{ "width_mismatch", "platform_dependent" } },
        };
    }

    /// Find a type mapping for a given source and target type.
    pub fn findTypeMapping(source_name: []const u8, target_name: []const u8) ?TypeMapping {
        const table = getTypeMappingTable();
        for (table) |mapping| {
            if (std.mem.eql(u8, mapping.source.type_name, source_name) and
                std.mem.eql(u8, mapping.target.type_name, target_name))
            {
                return mapping;
            }
        }
        return null;
    }
};

// ============================================================================
// Helper Functions
// ============================================================================

/// Create a LanguageType from basic parameters.
pub fn createLanguageType(
    language: []const u8,
    type_name: []const u8,
    bit_width: u32,
    is_signed: bool,
    alignment: u32,
    is_platform_dependent: bool,
) LanguageType {
    return .{
        .language = language,
        .type_name = type_name,
        .bit_width = bit_width,
        .is_signed = is_signed,
        .alignment = alignment,
        .is_platform_dependent = is_platform_dependent,
    };
}

/// Create a PointerType from basic parameters.
pub fn createPointerType(
    element_type: *const LanguageType,
    is_mutable: bool,
    is_raw: bool,
    bit_width: u32,
) PointerType {
    return .{
        .element_type = element_type,
        .is_mutable = is_mutable,
        .is_raw = is_raw,
        .bit_width = bit_width,
    };
}

/// Create an ArrayType from basic parameters.
pub fn createArrayType(
    element_type: *const LanguageType,
    length: u32,
    is_static: bool,
) ArrayType {
    return .{
        .element_type = element_type,
        .length = length,
        .is_static = is_static,
    };
}

/// Get the width difference between two types.
pub fn getWidthDifference(source: LanguageType, target: LanguageType) i32 {
    return @as(i32, @intCast(source.bit_width)) - @as(i32, @intCast(target.bit_width));
}

/// Check if a type is compatible with another type.
pub fn areTypesCompatible(source: LanguageType, target: LanguageType) bool {
    if (source.bit_width != target.bit_width) return false;
    if (source.is_signed != target.is_signed) return false;
    if (source.alignment < target.alignment) return false;
    if (source.is_platform_dependent and !target.is_platform_dependent) return false;
    return true;
}

/// Resolve platform-dependent type width for a given platform model.
pub fn resolveTypeWidth(lang_type: LanguageType, model: PlatformModel) u32 {
    // If not platform-dependent, return the fixed width
    if (!lang_type.is_platform_dependent) return lang_type.bit_width;

    // Platform-dependent C types
    if (std.mem.eql(u8, lang_type.language, "c")) {
        if (std.mem.eql(u8, lang_type.type_name, "long") or
            std.mem.eql(u8, lang_type.type_name, "unsigned long"))
        {
            return getCLongWidth(model);
        }
        if (std.mem.eql(u8, lang_type.type_name, "size_t") or
            std.mem.eql(u8, lang_type.type_name, "ssize_t") or
            std.mem.eql(u8, lang_type.type_name, "ptrdiff_t") or
            std.mem.eql(u8, lang_type.type_name, "intptr_t") or
            std.mem.eql(u8, lang_type.type_name, "uintptr_t"))
        {
            return getCPointerWidth(model);
        }
    }

    // Platform-dependent Zig/Rust types (usize, isize)
    if (std.mem.eql(u8, lang_type.type_name, "usize") or
        std.mem.eql(u8, lang_type.type_name, "isize"))
    {
        return getCPointerWidth(model);
    }

    // Default: return the stored width
    return lang_type.bit_width;
}

// ============================================================================
// Tests
// ============================================================================

test "PlatformModel - detection and widths" {
    try std.testing.expectEqual(PlatformModel.lp64, detectPlatformModel());
    try std.testing.expectEqual(@as(u32, 32), getCLongWidth(.ilp32));
    try std.testing.expectEqual(@as(u32, 64), getCLongWidth(.lp64));
    try std.testing.expectEqual(@as(u32, 32), getCLongWidth(.llp64));
    try std.testing.expectEqual(@as(u32, 32), getCPointerWidth(.ilp32));
    try std.testing.expectEqual(@as(u32, 64), getCPointerWidth(.lp64));
}

test "Zig types - properties and safe mapping" {
    try std.testing.expectEqualStrings("zig", zig_types.zig_i32.language);
    try std.testing.expectEqualStrings("i32", zig_types.zig_i32.type_name);
    try std.testing.expectEqual(@as(u32, 32), zig_types.zig_i32.bit_width);
    try std.testing.expect(zig_types.zig_i32.is_signed);
    try std.testing.expect(!zig_types.zig_i32.is_platform_dependent);
    try std.testing.expect(zig_types.zig_usize.is_platform_dependent);
    // Safe mapping to C
    var validator = TypeMappingValidator.init(std.testing.allocator);
    try std.testing.expect(validator.checkWidthMismatch(c_types.int32_t, zig_types.zig_i32) == null);
}

test "Python types - properties and safe mapping" {
    try std.testing.expectEqualStrings("python", python_types.py_c_int.language);
    try std.testing.expectEqualStrings("c_int", python_types.py_c_int.type_name);
    try std.testing.expect(python_types.py_c_size_t.is_platform_dependent);
    try std.testing.expectEqual(@as(u32, 64), python_types.py_c_void_p.bit_width);
    // Safe mapping to C
    var validator = TypeMappingValidator.init(std.testing.allocator);
    try std.testing.expect(validator.checkWidthMismatch(c_types.int32_t, python_types.py_c_int) == null);
}

test "Unsafe mappings - new patterns" {
    var validator = TypeMappingValidator.init(std.testing.allocator);
    // Go C.ulong -> Rust i32
    var issue = validator.checkUnsafeMapping(go_types.C_ulong, rust_types.rust_i32);
    try std.testing.expect(issue != null);
    try std.testing.expectEqual(TypeMismatchKind.unsafe_mapping, issue.?.kind);
    // Java jint -> C long
    issue = validator.checkUnsafeMapping(java_types.jint, c_types.long);
    try std.testing.expect(issue != null);
    // Python c_size_t -> Rust i32
    issue = validator.checkUnsafeMapping(python_types.py_c_size_t, rust_types.rust_i32);
    try std.testing.expect(issue != null);
    // Zig usize -> Rust i32
    issue = validator.checkUnsafeMapping(zig_types.zig_usize, rust_types.rust_i32);
    try std.testing.expect(issue != null);
}

test "Pointer validation - all mismatch types" {
    const allocator = std.testing.allocator;
    var validator = TypeMappingValidator.init(allocator);
    const int32 = c_types.int32_t;
    const int64 = c_types.int64_t;
    const loc = Location{ .file = "test.c", .line = 1, .column = 0 };
    var diag = DiagnosticWriter.init(allocator);

    // Mutability mismatch
    {
        var issues = validator.validatePointerType(
            createPointerType(&int32, true, false, 64),
            createPointerType(&int32, false, false, 64),
            loc,
            &diag,
        ) catch unreachable;
        defer allocator.free(issues);
        try std.testing.expect(issues.len > 0);
        try std.testing.expectEqual(PointerMismatchKind.mutability_mismatch, issues[0].kind);
    }

    // Element type mismatch
    {
        var issues = validator.validatePointerType(
            createPointerType(&int32, false, false, 64),
            createPointerType(&int64, false, false, 64),
            loc,
            &diag,
        ) catch unreachable;
        defer allocator.free(issues);
        var found = false;
        for (issues) |i| if (i.kind == .element_type_mismatch) found = true;
        try std.testing.expect(found);
    }

    // Compatible pointers
    {
        var issues = validator.validatePointerType(
            createPointerType(&int32, false, false, 64),
            createPointerType(&int32, false, false, 64),
            loc,
            &diag,
        ) catch unreachable;
        defer allocator.free(issues);
        try std.testing.expectEqual(@as(usize, 0), issues.len);
    }
}

test "Array validation - all mismatch types" {
    const allocator = std.testing.allocator;
    var validator = TypeMappingValidator.init(allocator);
    const int32 = c_types.int32_t;
    const int64 = c_types.int64_t;
    const loc = Location{ .file = "test.c", .line = 1, .column = 0 };
    var diag = DiagnosticWriter.init(allocator);

    // Length mismatch
    {
        var issues = validator.validateArrayType(createArrayType(&int32, 10, true), createArrayType(&int32, 20, true), loc, &diag) catch unreachable;
        defer allocator.free(issues);
        var found = false;
        for (issues) |i| if (i.kind == .length_mismatch) found = true;
        try std.testing.expect(found);
    }

    // Element type mismatch
    {
        var issues = validator.validateArrayType(createArrayType(&int32, 10, true), createArrayType(&int64, 10, true), loc, &diag) catch unreachable;
        defer allocator.free(issues);
        var found = false;
        for (issues) |i| if (i.kind == .element_type_mismatch) found = true;
        try std.testing.expect(found);
    }

    // Compatible arrays
    {
        var issues = validator.validateArrayType(createArrayType(&int32, 10, true), createArrayType(&int32, 10, true), loc, &diag) catch unreachable;
        defer allocator.free(issues);
        try std.testing.expectEqual(@as(usize, 0), issues.len);
    }
}

test "resolveTypeWidth - platform-dependent types" {
    try std.testing.expectEqual(@as(u32, 64), resolveTypeWidth(c_types.long, .lp64));
    try std.testing.expectEqual(@as(u32, 32), resolveTypeWidth(c_types.long, .ilp32));
    try std.testing.expectEqual(@as(u32, 32), resolveTypeWidth(c_types.int32_t, .lp64));
    try std.testing.expectEqual(@as(u32, 64), resolveTypeWidth(zig_types.zig_usize, .lp64));
    try std.testing.expectEqual(@as(u32, 32), resolveTypeWidth(zig_types.zig_usize, .ilp32));
}

test "TypeMappingValidator - basic mismatch checks" {
    var validator = TypeMappingValidator.init(std.testing.allocator);
    // Width mismatch
    var issue = validator.checkWidthMismatch(c_types.int32_t, c_types.int64_t);
    try std.testing.expect(issue != null);
    try std.testing.expectEqual(TypeMismatchKind.width_mismatch, issue.?.kind);
    // Sign mismatch
    issue = validator.checkSignMismatch(c_types.int32_t, c_types.unsigned_int);
    try std.testing.expect(issue != null);
    try std.testing.expectEqual(TypeMismatchKind.sign_mismatch, issue.?.kind);
    // Alignment mismatch
    issue = validator.checkAlignmentMismatch(c_types.int8_t, c_types.int32_t);
    try std.testing.expect(issue != null);
    try std.testing.expectEqual(TypeMismatchKind.alignment_mismatch, issue.?.kind);
    // Platform-dependent mismatch
    issue = validator.checkPlatformDependentMismatch(c_types.int32_t, c_types.int);
    try std.testing.expect(issue != null);
    try std.testing.expectEqual(TypeMismatchKind.platform_dependent_mismatch, issue.?.kind);
    // Unsafe mapping
    issue = validator.checkUnsafeMapping(rust_types.rust_i32, c_types.long);
    try std.testing.expect(issue != null);
    try std.testing.expectEqual(TypeMismatchKind.unsafe_mapping, issue.?.kind);
    // Safe mapping (all checks null)
    try std.testing.expect(validator.checkWidthMismatch(c_types.int32_t, rust_types.rust_i32) == null);
    try std.testing.expect(validator.checkSignMismatch(c_types.int32_t, rust_types.rust_i32) == null);
    try std.testing.expect(validator.checkAlignmentMismatch(c_types.int32_t, rust_types.rust_i32) == null);
    try std.testing.expect(validator.checkPlatformDependentMismatch(c_types.int32_t, rust_types.rust_i32) == null);
    try std.testing.expect(validator.checkUnsafeMapping(c_types.int32_t, rust_types.rust_i32) == null);
}

test "Helper functions - compatibility and width difference" {
    try std.testing.expect(areTypesCompatible(c_types.int32_t, rust_types.rust_i32));
    try std.testing.expect(!areTypesCompatible(c_types.int32_t, c_types.int64_t));
    try std.testing.expectEqual(@as(i32, 32), getWidthDifference(c_types.int64_t, c_types.int32_t));
    try std.testing.expectEqual(@as(i32, -32), getWidthDifference(c_types.int32_t, c_types.int64_t));
}

test "findTypeMapping and createLanguageType" {
    const mapping = TypeMappingValidator.findTypeMapping("int32_t", "i32");
    try std.testing.expect(mapping != null);
    try std.testing.expect(mapping.?.is_safe);
    try std.testing.expect(TypeMappingValidator.findTypeMapping("nonexistent", "type") == null);

    const lang_type = createLanguageType("test", "test_type", 32, true, 4, false);
    try std.testing.expectEqualStrings("test", lang_type.language);
    try std.testing.expectEqualStrings("test_type", lang_type.type_name);
    try std.testing.expectEqual(@as(u32, 32), lang_type.bit_width);
}

test "createPointerType and createArrayType" {
    const int32 = c_types.int32_t;
    const ptr_type = createPointerType(&int32, true, false, 64);
    try std.testing.expect(ptr_type.is_mutable);
    try std.testing.expect(!ptr_type.is_raw);
    try std.testing.expectEqualStrings("int32_t", ptr_type.element_type.type_name);

    const arr_type = createArrayType(&int32, 10, true);
    try std.testing.expectEqual(@as(u32, 10), arr_type.length);
    try std.testing.expect(arr_type.is_static);
}

test "initWithPlatform - custom platform model" {
    var validator = TypeMappingValidator.initWithPlatform(std.testing.allocator, .ilp32);
    try std.testing.expectEqual(PlatformModel.ilp32, validator.platform_model);
}
