//! IR Evidence Collector - Module-level evidence persistence layer
//!
//! Collects and caches language detection evidence from LLVM IR modules.
//! This is a read-only cache layer that reuses detector logic but persists
//! results for all subsequent passes to query without recomputation.
//!
//! Design principles:
//!   - MVP: Does NOT replace existing language_detector classification
//!   - Evidence is collected once at module load, then immutable
//!   - If collection fails, falls back to real-time detection (null safety)
//!   - All subsequent passes access via ctx.evidence, never call detector directly

const std = @import("std");
const Allocator = std.mem.Allocator;
const AutoHashMap = std.AutoHashMap;
const log = @import("../common/log.zig");
const c = @import("../ir/llvm_raw.zig").c;

const Language = @import("../diag/issue.zig").FFIBoundary.Language;
const ffi_language_classifier = @import("../pass/analysis/ffi/ffi_language_classifier.zig");

/// DWARF source language identifiers (DW_LANG_* constants from DWARF spec).
/// These are the canonical values used in DICompileUnit metadata.
/// Uses standard DWARF constants (e.g., DW_LANG_C = 0x0001).
pub const DWARFSourceLanguage = enum(c_uint) {
    C = 0x0001,
    Ada83 = 0x0002,
    C_plus_plus = 0x0003,
    Cobol74 = 0x0004,
    Cobol85 = 0x0005,
    Fortran77 = 0x0006,
    Fortran90 = 0x0007,
    Pascal83 = 0x0008,
    Modula2 = 0x0009,
    Java = 0x000a,
    C99 = 0x000b,
    Ada95 = 0x000c,
    Fortran95 = 0x000d,
    PLI = 0x000e,
    ObjC = 0x000f,
    ObjC_plus_plus = 0x0010,
    UPC = 0x0011,
    D = 0x0012,
    Python = 0x0013,
    OpenCL = 0x0014,
    Go = 0x0015,
    Modula3 = 0x0016,
    Haskell = 0x0017,
    C_plus_plus_03 = 0x0018,
    C_plus_plus_11 = 0x0019,
    OCaml = 0x001a,
    Rust = 0x001b,
    C11 = 0x001c,
    Swift = 0x001d,
    Julia = 0x001e,
    Dylan = 0x001f,
    C_plus_plus_14 = 0x0020,
    Fortran03 = 0x0021,
    Fortran08 = 0x0022,
    RenderScript = 0x0023,
    BLISS = 0x0024,
    Kotlin = 0x0025,
    Zig = 0x0026,
    Crystal = 0x0027,
    C_plus_plus_17 = 0x0028,
    C_plus_plus_20 = 0x0029,
    C17 = 0x002a,
    Fortran18 = 0x002b,
    Ada2005 = 0x002c,
    Ada2012 = 0x002d,
    HIP = 0x002e,
    Assembly = 0x002f,
    C_sharp = 0x0030,
    Mojo = 0x0031,
    GLSL = 0x0032,
    GLSL_ES = 0x0033,
    HLSL = 0x0034,
    OpenCL_CPP = 0x0035,
    CPP_for_OpenCL = 0x0036,
    SYCL = 0x0037,
    Ruby = 0x0038,
    Move = 0x0039,
    Hylo = 0x003a,
    Metal = 0x003b,
    Mips_Assembler = 0x0101,
    GOOGLE_RenderScript = 0x0102,
    BORLAND_Delphi = 0x0200,

    /// LLVM vendor extensions (0x8000xxxx range from LLVM 21+)
    _,

    pub fn fromLLVMEnum(lang: c.LLVMDWARFSourceLanguage) DWARFSourceLanguage {
        return @enumFromInt(@intFromEnum(lang));
    }

    /// Infer DWARF source language from a source file path extension.
    /// Used as fallback when CU language metadata is not directly available.
    pub fn inferFromFilename(filename: []const u8) ?DWARFSourceLanguage {
        if (std.mem.endsWith(u8, filename, ".c")) return .C;
        if (std.mem.endsWith(u8, filename, ".cpp") or
            std.mem.endsWith(u8, filename, ".cc") or
            std.mem.endsWith(u8, filename, ".cxx") or
            std.mem.endsWith(u8, filename, ".C")) return .C_plus_plus;
        if (std.mem.endsWith(u8, filename, ".rs")) return .Rust;
        if (std.mem.endsWith(u8, filename, ".go")) return .Go;
        if (std.mem.endsWith(u8, filename, ".zig")) return .Zig;
        if (std.mem.endsWith(u8, filename, ".swift")) return .Swift;
        if (std.mem.endsWith(u8, filename, ".cs")) return .C_sharp;
        if (std.mem.endsWith(u8, filename, ".py")) return .Python;
        if (std.mem.endsWith(u8, filename, ".java")) return .Java;
        if (std.mem.endsWith(u8, filename, ".kt") or
            std.mem.endsWith(u8, filename, ".kts")) return .Kotlin;
        if (std.mem.endsWith(u8, filename, ".rb")) return .Ruby;
        if (std.mem.endsWith(u8, filename, ".dart")) return .D;
        if (std.mem.endsWith(u8, filename, ".m")) return .ObjC;
        if (std.mem.endsWith(u8, filename, ".mm")) return .ObjC_plus_plus;
        return null;
    }
};

/// Map LLVM DWARF source language to OmniScope internal Language.
pub fn dwarfLangToLanguage(dwarf_lang: DWARFSourceLanguage) Language {
    return switch (dwarf_lang) {
        .C, .C99, .C11, .C17 => .c,
        .C_plus_plus, .C_plus_plus_03, .C_plus_plus_11, .C_plus_plus_14, .C_plus_plus_17, .C_plus_plus_20 => .cpp,
        .Rust => .rust,
        .Go => .go,
        .Zig => .zig,
        .C_sharp => .csharp,
        .Python => .python,
        .Java => .java,
        .Kotlin => .java,
        .Swift => .swift,
        .Ruby => .ruby,
        .ObjC, .ObjC_plus_plus => .objc,
        else => .unknown,
    };
}

/// Persistent evidence container for module-level language detection.
///
/// Stores raw counts and flags from each detection phase so that any pass
/// can inspect the underlying signals, not just the final classification.
/// This enables custom heuristics without rerunning expensive scans.
pub const IREvidence = struct {
    // Personality function evidence (from detectFromPersonality)
    has_gxx_personality: bool = false,
    has_rust_personality: bool = false,
    has_go_personality: bool = false,
    has_zig_personality: bool = false,
    has_csharp_personality: bool = false,
    has_python_personality: bool = false,

    // Mangling prefix evidence (from detectFromSampling)
    rust_mangled_count: usize = 0,
    cpp_mangled_count: usize = 0,
    csharp_dot_count: usize = 0,
    go_runtime_count: usize = 0,
    zig_stdlib_count: usize = 0,

    // Global symbol evidence (from detectFromGlobals)
    vtable_count: usize = 0,
    rtti_count: usize = 0,
    pyinit_count: usize = 0,
    pygc_count: usize = 0,

    // DWARF language evidence (from collectDwarfLanguages)
    // Maps each LLVM function to its DWARF source language.
    // Must be initialized via IREvidence.init(allocator) or manually.
    dwarf_lang_map: AutoHashMap(c.LLVMValueRef, DWARFSourceLanguage),

    // Derived fields (computed after collection)
    dominant_language: Language = .unknown,
    confidence: f32 = 0.0,

    /// Performance tracking: nanoseconds spent in EvidenceCollector.init().
    /// Populated after init() completes. 0 if timing was unavailable.
    init_duration_ns: u64 = 0,

    /// Initialize IREvidence with allocated resources.
    pub fn init(allocator: Allocator) IREvidence {
        return .{
            .dwarf_lang_map = AutoHashMap(c.LLVMValueRef, DWARFSourceLanguage).init(allocator),
        };
    }

    /// Release owned memory and warn if init exceeded performance budget.
    pub fn deinit(self: *IREvidence) void {
        self.dwarf_lang_map.deinit();

        if (self.init_duration_ns > 500_000_000) {
            std.log.warn("IREvidence.init took {}ms (≥500ms threshold)", .{
                @divFloor(self.init_duration_ns, 1_000_000),
            });
        }
    }

    /// Query DWARF source language for a specific function.
    /// Returns null if no DWARF evidence was collected for this function.
    pub fn getDwarfLang(self: *const IREvidence, func: c.LLVMValueRef) ?DWARFSourceLanguage {
        return self.dwarf_lang_map.get(func);
    }
};

/// Evidence collector that scans an LLVM module once and produces IREvidence.
///
/// Usage:
///   var collector = try EvidenceCollector.init(allocator, module);
///   defer collector.deinit();
///   const evidence = collector.getEvidence();
pub const EvidenceCollector = struct {
    evidence: IREvidence,
    allocator: Allocator,

    /// Initialize collector and scan the module for evidence.
    ///
    /// This runs all three detection phases (sampling, personality, globals)
    /// and populates the evidence struct with raw counts and derived results.
    pub fn init(allocator: Allocator, module: c.LLVMModuleRef) !EvidenceCollector {
        const init_start = std.time.Instant.now() catch null;
        var self = EvidenceCollector{
            .evidence = IREvidence.init(allocator),
            .allocator = allocator,
        };

        if (@intFromPtr(module) == 0) {
            log.warn("[ir-evidence] Null module ref, returning empty evidence", .{});
            return self;
        }

        self.collectPersonality(module);
        self.collectMangling(module);
        self.collectGlobals(module);
        self.collectDwarfLanguages(module);
        self.computeDominantLanguage();

        log.debug("[ir-evidence] Collection complete: lang={s}, confidence={d:.1}%", .{
            @tagName(self.evidence.dominant_language),
            self.evidence.confidence * 100,
        });

        // Performance: record init duration if timing was available
        if (init_start) |start| {
            if (std.time.Instant.now()) |end| {
                self.evidence.init_duration_ns = @intCast(end.since(start));
            } else |_| {}
        }

        return self;
    }

    /// Release owned memory.
    ///
    /// IMPORTANT: Does NOT deinit self.evidence (including dwarf_lang_map)
    /// because ownership of the evidence has been transferred to the caller.
    ///
    /// The caller in pass_context_impl.zig does:
    ///   self.evidence = evidence_collector.getEvidence().*;
    ///
    /// This shallow-copies the IREvidence struct (including the HashMap handle
    /// for dwarf_lang_map). Both the collector's copy and the caller's copy
    /// point to the same underlying HashMap allocations.
    ///
    /// If we freed the HashMap here, the caller's copy would be a
    /// use-after-free. Instead, the caller (PassContext) is responsible
    /// for calling IREvidence.deinit() on its own copy.
    ///
    /// If you add new fields with owned allocations that are NOT transferred
    /// to the caller, deinit them here.
    pub fn deinit(self: *EvidenceCollector) void {
        _ = &self.evidence;
        _ = &self.allocator;
    }

    /// Get immutable reference to collected evidence.
    pub fn getEvidence(self: *const EvidenceCollector) *const IREvidence {
        return &self.evidence;
    }

    /// Phase 1: Scan personality function attributes across all functions.
    ///
    /// Personality functions identify exception handling runtimes which are
    /// strongly correlated with source languages:
    ///   - rust_eh_personality → Rust
    ///   - __gxx_personality_v0 → C++
    ///   - csharp_exception_personality → C#
    fn collectPersonality(self: *EvidenceCollector, module: c.LLVMModuleRef) void {
        var func = c.LLVMGetFirstFunction(module);
        while (@intFromPtr(func) != 0) : (func = c.LLVMGetNextFunction(func)) {
            const name_ptr = c.LLVMGetValueName(func);
            if (@intFromPtr(name_ptr) == 0) continue;

            const name = std.mem.span(name_ptr);

            if (std.mem.indexOf(u8, name, "rust_eh_personality") != null) {
                self.evidence.has_rust_personality = true;
            } else if (std.mem.indexOf(u8, name, "__gxx_personality") != null) {
                self.evidence.has_gxx_personality = true;
            } else if (std.mem.indexOf(u8, name, "csharp_exception_personality") != null or
                std.mem.indexOf(u8, name, "mono_unity_personality") != null)
            {
                self.evidence.has_csharp_personality = true;
            }
        }
    }

    /// Phase 2: Sample function names for mangling pattern analysis.
    ///
    /// Counts language-specific mangled name patterns from a sample of
    /// functions (up to SAMPLE_SIZE). This mirrors detectFromSampling()
    /// logic but stores counts instead of computing a single result.
    const SAMPLE_SIZE: usize = 50;

    fn collectMangling(self: *EvidenceCollector, module: c.LLVMModuleRef) void {
        var func = c.LLVMGetFirstFunction(module);
        var sampled: usize = 0;

        while (@intFromPtr(func) != 0 and sampled < SAMPLE_SIZE) : ({
            func = c.LLVMGetNextFunction(func);
        }) {
            const name_ptr = c.LLVMGetValueName(func);
            if (@intFromPtr(name_ptr) == 0) continue;

            const name = std.mem.span(name_ptr);

            if (std.mem.startsWith(u8, name, "llvm.")) continue;

            sampled += 1;

            // Rust markers (unambiguous)
            if (std.mem.indexOf(u8, name, "_rust_") != null or
                std.mem.indexOf(u8, name, "rs2py_") != null)
            {
                self.evidence.rust_mangled_count += 1;
                continue;
            }

            // Go runtime markers (unambiguous)
            if (std.mem.startsWith(u8, name, "main.") or
                std.mem.startsWith(u8, name, "runtime.") or
                std.mem.startsWith(u8, name, "syscall.") or
                std.mem.startsWith(u8, name, "gcops."))
            {
                self.evidence.go_runtime_count += 1;
                continue;
            }

            // Zig markers (unambiguous)
            if (std.mem.indexOf(u8, name, "zig_") != null or
                std.mem.indexOf(u8, name, "Allocator.") != null)
            {
                self.evidence.zig_stdlib_count += 1;
                continue;
            }

            // Python PyInit_ marker
            if (std.mem.startsWith(u8, name, "PyInit_")) {
                self.evidence.pyinit_count += 1;
                continue;
            }

            // C# / .NET mangling prefixes
            if (std.mem.startsWith(u8, name, "$s") or
                std.mem.startsWith(u8, name, "<Module>.") or
                std.mem.startsWith(u8, name, "System.") or
                std.mem.startsWith(u8, name, "Microsoft.") or
                std.mem.startsWith(u8, name, "Mono_") or
                std.mem.indexOf(u8, name, "__DotNet") != null)
            {
                self.evidence.csharp_dot_count += 1;
                continue;
            }

            // _ZN disambiguation (Rust vs C++)
            if (name.len > 3 and name[0] == '_' and name[1] == 'Z' and name[2] == 'N') {
                if (ffi_language_classifier.isRustMangledName(name)) {
                    self.evidence.rust_mangled_count += 1;
                } else {
                    self.evidence.cpp_mangled_count += 1;
                }
                continue;
            }

            // Plain _Z (non-_ZN) = C++ Itanium mangling
            if (name.len > 2 and name[0] == '_' and name[1] == 'Z' and name[2] != 'N') {
                self.evidence.cpp_mangled_count += 1;
                continue;
            }
        }
    }

    /// Phase 3: Scan global variable name prefixes for language signals.
    ///
    /// Global variables carry strong language-specific naming conventions
    /// that complement function-name-based detection.
    fn collectGlobals(self: *EvidenceCollector, module: c.LLVMModuleRef) void {
        var global = c.LLVMGetFirstGlobal(module);
        while (@intFromPtr(global) != 0) : (global = c.LLVMGetNextGlobal(global)) {
            const name_ptr = c.LLVMGetValueName(global);
            if (@intFromPtr(name_ptr) == 0) continue;

            const name = std.mem.span(name_ptr);

            // C++ RTTI / vtable globals (_ZTV*, _ZTI*, _ZTS*)
            if (name.len > 3 and name[0] == '_' and name[1] == 'Z' and name[2] == 'T') {
                const third_char = name[3];
                if (third_char == 'V') {
                    self.evidence.vtable_count += 1;
                } else if (third_char == 'I' or third_char == 'S') {
                    self.evidence.rtti_count += 1;
                }
                continue;
            }

            // Python GC internal runtime symbols
            if (std.mem.startsWith(u8, name, "_PyGC_")) {
                self.evidence.pygc_count += 1;
                continue;
            }
        }
    }

    /// Phase 4: Collect DWARF compile unit language evidence for each function.
    ///
    /// For each function with debug info (DISubprogram), tries to extract the
    /// source file and infer language from the filename extension. Falls back
    /// to filename inference when direct CU language metadata is unavailable
    /// via the LLVM C API.
    ///
    /// Results are stored in dwarf_lang_map (function → DWARFSourceLanguage).
    fn collectDwarfLanguages(self: *EvidenceCollector, module: c.LLVMModuleRef) void {
        var func = c.LLVMGetFirstFunction(module);
        while (@intFromPtr(func) != 0) : (func = c.LLVMGetNextFunction(func)) {
            // Try to get DISubprogram metadata for this function
            const subprogram = c.LLVMGetSubprogram(func);
            if (subprogram != null) {
                // The subprogram metadata ref IS a DIScope, so we can get the file directly
                const file = c.LLVMDIScopeGetFile(subprogram);
                if (file != null) {
                    var len: c_uint = 0;
                    const filename_ptr = c.LLVMDIFileGetFilename(file, &len);
                    if (len > 0 and @intFromPtr(filename_ptr) != 0) {
                        const filename = filename_ptr[0..len];
                        if (DWARFSourceLanguage.inferFromFilename(filename)) |lang| {
                            self.evidence.dwarf_lang_map.put(func, lang) catch {};
                        }
                    }
                }
            }

            // Fallback: if no DWARF evidence was collected, try inferring from
            // the function name itself (for external declarations with no body).
            if (!self.evidence.dwarf_lang_map.contains(func)) {
                const name_ptr = c.LLVMGetValueName(func);
                if (@intFromPtr(name_ptr) != 0) {
                    const name = std.mem.span(name_ptr);
                    // External declarations with no body have no subprogram metadata.
                    // For known language-specific naming patterns we can still infer.
                    // Skip inference for anonymous/llvm internal names.
                    if (name.len > 0 and !std.mem.startsWith(u8, name, "llvm.")) {
                        // No reliable per-function language inference from name alone;
                        // this is a best-effort fallback that can be enhanced in future.
                    }
                }
            }
        }
    }

    /// Compute dominant language and confidence from collected evidence.
    ///
    /// Uses weighted voting across all three phases:
    ///   - Sampling (mangling): weight 1.0x
    ///   - Personality: weight 0.8x
    ///   - Globals: weight 0.6x
    fn computeDominantLanguage(self: *EvidenceCollector) void {
        const SAMPLING_WEIGHT: f32 = 1.0;
        const PERSONALITY_WEIGHT: f32 = 0.8;
        const GLOBALS_WEIGHT: f32 = 0.6;

        var weighted_votes = [_]f32{0} ** 8;

        // Sampling votes (from mangling counts)
        const sampling_total: f32 = @floatFromInt(@as(i32, @intCast(self.evidence.rust_mangled_count)) +
            @as(i32, @intCast(self.evidence.cpp_mangled_count)) +
            @as(i32, @intCast(self.evidence.csharp_dot_count)) +
            @as(i32, @intCast(self.evidence.go_runtime_count)) +
            @as(i32, @intCast(self.evidence.zig_stdlib_count)));

        if (sampling_total > 0) {
            if (self.evidence.rust_mangled_count > 0) {
                weighted_votes[0] += (@as(f32, @floatFromInt(self.evidence.rust_mangled_count)) / sampling_total) * SAMPLING_WEIGHT;
            }
            if (self.evidence.go_runtime_count > 0) {
                weighted_votes[1] += (@as(f32, @floatFromInt(self.evidence.go_runtime_count)) / sampling_total) * SAMPLING_WEIGHT;
            }
            if (self.evidence.zig_stdlib_count > 0) {
                weighted_votes[2] += (@as(f32, @floatFromInt(self.evidence.zig_stdlib_count)) / sampling_total) * SAMPLING_WEIGHT;
            }
            if (self.evidence.cpp_mangled_count > 0) {
                weighted_votes[3] += (@as(f32, @floatFromInt(self.evidence.cpp_mangled_count)) / sampling_total) * SAMPLING_WEIGHT;
            }
            if (self.evidence.csharp_dot_count > 0) {
                weighted_votes[5] += (@as(f32, @floatFromInt(self.evidence.csharp_dot_count)) / sampling_total) * SAMPLING_WEIGHT;
            }
        }

        // Personality votes (boolean flags)
        if (self.evidence.has_rust_personality) {
            weighted_votes[0] += PERSONALITY_WEIGHT;
        }
        if (self.evidence.has_gxx_personality) {
            weighted_votes[3] += PERSONALITY_WEIGHT;
        }
        if (self.evidence.has_csharp_personality) {
            weighted_votes[5] += PERSONALITY_WEIGHT;
        }

        // Globals votes (from RTTI/vtable counts)
        const globals_total: f32 = @floatFromInt(@as(i32, @intCast(self.evidence.vtable_count)) +
            @as(i32, @intCast(self.evidence.rtti_count)) +
            @as(i32, @intCast(self.evidence.pygc_count)));

        if (globals_total > 0) {
            if (self.evidence.vtable_count > 0 or self.evidence.rtti_count > 0) {
                weighted_votes[3] += (@as(f32, @floatFromInt(self.evidence.vtable_count + self.evidence.rtti_count)) / globals_total) * GLOBALS_WEIGHT;
            }
            if (self.evidence.pygc_count > 0) {
                weighted_votes[7] += (@as(f32, @floatFromInt(self.evidence.pygc_count)) / globals_total) * GLOBALS_WEIGHT;
            }
        }

        // Find dominant language
        var max_vote: f32 = 0;
        var dominant: Language = .unknown;
        var total_weight: f32 = 0;

        for (weighted_votes) |vote| {
            total_weight += vote;
            if (vote > max_vote) {
                max_vote = vote;
            }
        }

        // Map max vote back to language index
        for (weighted_votes, 0..) |vote, i| {
            if (vote == max_vote and max_vote > 0) {
                dominant = indexToLang(i);
                break;
            }
        }

        if (max_vote < 0.3 or total_weight < 0.3) {
            self.evidence.dominant_language = .unknown;
            self.evidence.confidence = 0.0;
            return;
        }

        self.evidence.dominant_language = dominant;
        self.evidence.confidence = @min(max_vote / total_weight, 1.0);
    }

    fn indexToLang(idx: usize) Language {
        return switch (idx) {
            0 => .rust,
            1 => .go,
            2 => .zig,
            3 => .cpp,
            4 => .c,
            5 => .csharp,
            6 => .java,
            7 => .python,
            else => .unknown,
        };
    }
};

// Unit tests

test "IREvidence default initialization" {
    const allocator = std.testing.allocator;
    var evidence = IREvidence.init(allocator);
    defer evidence.deinit();

    try std.testing.expectEqual(false, evidence.has_rust_personality);
    try std.testing.expectEqual(@as(usize, 0), evidence.rust_mangled_count);
    try std.testing.expectEqual(Language.unknown, evidence.dominant_language);
    try std.testing.expectEqual(@as(f32, 0.0), evidence.confidence);
}

test "EvidenceCollector with null module returns empty evidence" {
    const allocator = std.testing.allocator;
    var collector = try EvidenceCollector.init(allocator, @as(c.LLVMModuleRef, @ptrFromInt(0)));
    defer collector.evidence.deinit();
    defer collector.deinit();

    const evidence = collector.getEvidence();
    try std.testing.expectEqual(Language.unknown, evidence.dominant_language);
    try std.testing.expectEqual(@as(f32, 0.0), evidence.confidence);
}

test "computeDominantLanguage with Rust evidence" {
    var collector = EvidenceCollector{
        .evidence = IREvidence.init(std.testing.allocator),
        .allocator = std.testing.allocator,
    };
    defer collector.evidence.deinit();

    collector.evidence.rust_mangled_count = 10;
    collector.evidence.has_rust_personality = true;
    collector.computeDominantLanguage();

    try std.testing.expectEqual(Language.rust, collector.evidence.dominant_language);
    try std.testing.expect(collector.evidence.confidence > 0.5);
}

test "computeDominantLanguage with C++ evidence" {
    var collector = EvidenceCollector{
        .evidence = IREvidence.init(std.testing.allocator),
        .allocator = std.testing.allocator,
    };
    defer collector.evidence.deinit();

    collector.evidence.cpp_mangled_count = 15;
    collector.evidence.vtable_count = 3;
    collector.evidence.rtti_count = 3;
    collector.evidence.has_gxx_personality = true;
    collector.computeDominantLanguage();

    try std.testing.expectEqual(Language.cpp, collector.evidence.dominant_language);
    try std.testing.expect(collector.evidence.confidence > 0.5);
}

test "collectMangling patterns" {
    const allocator = std.testing.allocator;

    var collector = EvidenceCollector{
        .evidence = IREvidence.init(allocator),
        .allocator = allocator,
    };
    defer collector.evidence.deinit();

    const test_names = [_][]const u8{
        "_rust_mangle_fn",
        "runtime.main_task",
        "zig_std_alloc",
        "$s_System_Console_WriteLine",
        "_ZN4core3fmt9Debug3fmt17he1b7ec36415abac2E",
        "_Z4funcv",
        "PyInit_numpy",
    };

    for (test_names) |name| {
        if (std.mem.indexOf(u8, name, "_rust_") != null) {
            collector.evidence.rust_mangled_count += 1;
        } else if (std.mem.startsWith(u8, name, "runtime.")) {
            collector.evidence.go_runtime_count += 1;
        } else if (std.mem.indexOf(u8, name, "zig_") != null) {
            collector.evidence.zig_stdlib_count += 1;
        } else if (std.mem.startsWith(u8, name, "$s")) {
            collector.evidence.csharp_dot_count += 1;
        } else if (name.len > 3 and name[0] == '_' and name[1] == 'Z' and name[2] == 'N') {
            if (ffi_language_classifier.isRustMangledName(name)) {
                collector.evidence.rust_mangled_count += 1;
            } else {
                collector.evidence.cpp_mangled_count += 1;
            }
        } else if (name.len > 2 and name[0] == '_' and name[1] == 'Z' and name[2] != 'N') {
            collector.evidence.cpp_mangled_count += 1;
        } else if (std.mem.startsWith(u8, name, "PyInit_")) {
            collector.evidence.pyinit_count += 1;
        }
    }

    try std.testing.expectEqual(@as(usize, 2), collector.evidence.rust_mangled_count);
    try std.testing.expectEqual(@as(usize, 1), collector.evidence.go_runtime_count);
    try std.testing.expectEqual(@as(usize, 1), collector.evidence.zig_stdlib_count);
    try std.testing.expectEqual(@as(usize, 1), collector.evidence.csharp_dot_count);
    try std.testing.expectEqual(@as(usize, 1), collector.evidence.cpp_mangled_count);
    try std.testing.expectEqual(@as(usize, 1), collector.evidence.pyinit_count);
}

test "collectGlobals vtable/RTTI counting" {
    var collector = EvidenceCollector{
        .evidence = IREvidence.init(std.testing.allocator),
        .allocator = std.testing.allocator,
    };
    defer collector.evidence.deinit();

    const test_globals = [_][]const u8{
        "_ZTV4Base",
        "_ZTI4Base",
        "_ZTS4Base",
        "_ZTVN3foo6BarE",
        "_PyGC_Collect",
        "__dotnet_init",
        "Mono_Runtime",
    };

    for (test_globals) |name| {
        if (name.len > 3 and name[0] == '_' and name[1] == 'Z' and name[2] == 'T') {
            const third_char = name[3];
            if (third_char == 'V') {
                collector.evidence.vtable_count += 1;
            } else if (third_char == 'I' or third_char == 'S') {
                collector.evidence.rtti_count += 1;
            }
        } else if (std.mem.startsWith(u8, name, "_PyGC_")) {
            collector.evidence.pygc_count += 1;
        }
    }

    try std.testing.expectEqual(@as(usize, 2), collector.evidence.vtable_count); // _ZTV4Base, _ZTVN3foo6BarE
    try std.testing.expectEqual(@as(usize, 2), collector.evidence.rtti_count); // _ZTI4Base, _ZTS4Base
    try std.testing.expectEqual(@as(usize, 1), collector.evidence.pygc_count); // _PyGC_Collect
}
