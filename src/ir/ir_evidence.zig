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
const log = @import("../common/log.zig");
const c = @import("../ir/llvm_raw.zig").c;

const Language = @import("../diag/issue.zig").FFIBoundary.Language;
const ffi_language_classifier = @import("../pass/analysis/ffi/ffi_language_classifier.zig");

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

    // Derived fields (computed after collection)
    dominant_language: Language = .unknown,
    confidence: f32 = 0.0,
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
        var self = EvidenceCollector{
            .evidence = .{},
            .allocator = allocator,
        };

        if (@intFromPtr(module) == 0) {
            log.warn("[ir-evidence] Null module ref, returning empty evidence", .{});
            return self;
        }

        self.collectPersonality(module);
        self.collectMangling(module);
        self.collectGlobals(module);
        self.computeDominantLanguage();

        log.debug("[ir-evidence] Collection complete: lang={s}, confidence={d:.1}%", .{
            @tagName(self.evidence.dominant_language),
            self.evidence.confidence * 100,
        });

        return self;
    }

    /// Release owned memory.
    pub fn deinit(self: *EvidenceCollector) void {
        _ = self;
        // No owned buffers in MVP
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
    const evidence = IREvidence{};

    try std.testing.expectEqual(false, evidence.has_rust_personality);
    try std.testing.expectEqual(@as(usize, 0), evidence.rust_mangled_count);
    try std.testing.expectEqual(Language.unknown, evidence.dominant_language);
    try std.testing.expectEqual(@as(f32, 0.0), evidence.confidence);
}

test "EvidenceCollector with null module returns empty evidence" {
    const allocator = std.testing.allocator;
    var collector = try EvidenceCollector.init(allocator, @as(c.LLVMModuleRef, @ptrFromInt(0)));
    defer collector.deinit();

    const evidence = collector.getEvidence();
    try std.testing.expectEqual(Language.unknown, evidence.dominant_language);
    try std.testing.expectEqual(@as(f32, 0.0), evidence.confidence);
}

test "computeDominantLanguage with Rust evidence" {
    var collector = EvidenceCollector{
        .evidence = .{},
        .allocator = std.testing.allocator,
    };

    collector.evidence.rust_mangled_count = 10;
    collector.evidence.has_rust_personality = true;
    collector.computeDominantLanguage();

    try std.testing.expectEqual(Language.rust, collector.evidence.dominant_language);
    try std.testing.expect(collector.evidence.confidence > 0.5);
}

test "computeDominantLanguage with C++ evidence" {
    var collector = EvidenceCollector{
        .evidence = .{},
        .allocator = std.testing.allocator,
    };

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
        .evidence = .{},
        .allocator = allocator,
    };

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
        .evidence = .{},
        .allocator = std.testing.allocator,
    };

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
