//! Pipeline Runner — Single-file analysis orchestration
//!
//! Higher-level runner that loads a file, runs the pipeline via pipeline.zig,
//! detects languages, formats output, and optionally generates visualizations.

const std = @import("std");
const Allocator = std.mem.Allocator;
const OmniScope = @import("OmniScope");
const IRLoader = OmniScope.engine.IRLoader;
const Issue = OmniScope.diag.Issue;
const log = OmniScope.log;

const Config = OmniScope.config.main_config.Config;
const LanguageDetector = OmniScope.semantics.language_detector;

const pipeline = @import("pipeline.zig");
const ffi_precision = @import("ffi_precision.zig");
const output_formatter = @import("output_formatter.zig");
const c = OmniScope.ir.llvm_raw.c;

pub const AnalyzeResult = pipeline.AnalyzeResult;

pub fn runSingleFileAnalysis(allocator: std.mem.Allocator, path: []const u8, config: Config) !void {
    log.info("=== OmniScope IR Analysis ===\n", .{});
    log.info("File: {s}\n\n", .{path});

    var loader = IRLoader.loadFile(allocator, path) catch |err| {
        log.err("Failed to load IR file: {s}\n", .{@errorName(err)});
        return err;
    };
    defer loader.deinit();

    const source_lang = if (loader.getModule()) |module_ref|
        LanguageDetector.detectModuleLanguage(module_ref.raw, allocator)
    else
        LanguageDetector.LanguageProfile{ .language = .unknown, .confidence = 0.0, .method = .unknown };

    const source_lang_name = output_formatter.languageDisplayName(source_lang.language);
    log.info("[Language] Source: {s} (confidence: {:.1}%)\n", .{ source_lang_name, source_lang.confidence * 100 });
    log.debug("Loaded: {d} functions\n\n", .{loader.getFunctionCount()});

    // P0: If the module is a single language, skip entirely — OmniScope analyzes
    // cross-language FFI boundaries only. Pure single-language modules (C-only,
    // Rust-only, etc.) have nothing to find by design. We check function name
    // patterns from ALL supported languages below to detect multi-language content.
    if (source_lang.language != .unknown) {
        // Double-check: Even with high confidence, verify there are no functions
        // from OTHER languages that would indicate mixed-language content.
        // This prevents misclassifying Rust+SQLite binaries as pure C.
        var has_multi_lang_hint = false;
        if (loader.getModule()) |module_ref| {
            var func = c.LLVMGetFirstFunction(module_ref.raw);
            while (@intFromPtr(func) != 0) : (func = c.LLVMGetNextFunction(func)) {
                const name_ptr = c.LLVMGetValueName(func);
                if (@intFromPtr(name_ptr) == 0) continue;
                const name = std.mem.span(name_ptr);
                if (std.mem.startsWith(u8, name, "llvm.")) continue;

                // ═══════════════════════════════════════════════════════
                // Comprehensive multi-language hint detection
                // Covers ALL 8 supported languages: Rust, Go, Zig, C++,
                // C#, Java, Python, C — each check is gated by
                // source_lang so we only flag functions from OTHER languages.
                // ═══════════════════════════════════════════════════════

                // ── Rust ──────────────────────────────────────────
                // Rust v0 mangling (_R...) — unambiguous
                if (name.len > 2 and name[0] == '_' and name[1] == 'R') {
                    if (source_lang.language != .rust) {
                        has_multi_lang_hint = true;
                        break;
                    }
                }
                // Rust/C++ _ZN mangling (disambiguate via isRustMangledName)
                if (name.len > 3 and name[0] == '_' and name[1] == 'Z' and name[2] == 'N') {
                    if (source_lang.language != .rust and source_lang.language != .cpp) {
                        has_multi_lang_hint = true;
                        break;
                    }
                }
                // C++ _Z (non-_ZN) mangling — unambiguous C++
                if (name.len > 2 and name[0] == '_' and name[1] == 'Z' and name[2] != 'N') {
                    if (source_lang.language != .cpp) {
                        has_multi_lang_hint = true;
                        break;
                    }
                }
                // Rust strong prefixes
                if (std.mem.startsWith(u8, name, "_rust_") or
                    std.mem.startsWith(u8, name, "rs2py_"))
                {
                    if (source_lang.language != .rust) {
                        has_multi_lang_hint = true;
                        break;
                    }
                }
                // Rust personality/eH / unwind
                if (std.mem.indexOf(u8, name, "rust_eh_personality") != null or
                    std.mem.indexOf(u8, name, "rust_begin_unwind") != null or
                    std.mem.indexOf(u8, name, "rust_oom") != null or
                    std.mem.startsWith(u8, name, "__rust_"))
                {
                    if (source_lang.language != .rust) {
                        has_multi_lang_hint = true;
                        break;
                    }
                }

                // ── C++ ──────────────────────────────────────────
                // C++ personality, EH, RTTI
                if (std.mem.indexOf(u8, name, "__gxx_personality") != null or
                    std.mem.startsWith(u8, name, "__cxa_") or
                    std.mem.startsWith(u8, name, "_ZTV") or // C++ vtable
                    std.mem.startsWith(u8, name, "_ZTI") or // C++ typeinfo
                    std.mem.startsWith(u8, name, "_ZTS")) // C++ typeinfo name
                {
                    if (source_lang.language != .cpp) {
                        has_multi_lang_hint = true;
                        break;
                    }
                }

                // ── Go ───────────────────────────────────────────
                // Go strong prefixes
                if (std.mem.startsWith(u8, name, "runtime.") or
                    std.mem.startsWith(u8, name, "main.") or
                    std.mem.startsWith(u8, name, "syscall.") or
                    std.mem.startsWith(u8, name, "gcops.") or
                    std.mem.startsWith(u8, name, "reflect.") or
                    std.mem.startsWith(u8, name, "internal/") or
                    std.mem.startsWith(u8, name, "__go_") or
                    std.mem.indexOf(u8, name, "_Cgo_") != null)
                {
                    if (source_lang.language != .go) {
                        has_multi_lang_hint = true;
                        break;
                    }
                }

                // ── Zig ──────────────────────────────────────────
                if (std.mem.startsWith(u8, name, "zig_") or
                    std.mem.indexOf(u8, name, "Allocator.") != null or
                    std.mem.startsWith(u8, name, "zig.") or
                    std.mem.startsWith(u8, name, "__zig_"))
                {
                    if (source_lang.language != .zig) {
                        has_multi_lang_hint = true;
                        break;
                    }
                }

                // ── Java / JNI ────────────────────────────────────
                if (std.mem.startsWith(u8, name, "Java_") or
                    std.mem.startsWith(u8, name, "JNI_OnLoad") or
                    std.mem.startsWith(u8, name, "JNI_OnUnload"))
                {
                    if (source_lang.language != .java) {
                        has_multi_lang_hint = true;
                        break;
                    }
                }

                // ── Python ────────────────────────────────────────
                if (std.mem.startsWith(u8, name, "PyInit_") or
                    std.mem.startsWith(u8, name, "Py_") or
                    std.mem.startsWith(u8, name, "PyObject_") or
                    std.mem.startsWith(u8, name, "_PyGC_") or
                    std.mem.startsWith(u8, name, "_Py_"))
                {
                    if (source_lang.language != .python) {
                        has_multi_lang_hint = true;
                        break;
                    }
                }

                // ── C# / .NET ─────────────────────────────────────
                if (std.mem.startsWith(u8, name, "System.") or
                    std.mem.startsWith(u8, name, "Microsoft.") or
                    std.mem.startsWith(u8, name, "Mono_") or
                    std.mem.startsWith(u8, name, "$s") or
                    std.mem.startsWith(u8, name, "<Module>.") or
                    std.mem.startsWith(u8, name, "GC_") or
                    std.mem.startsWith(u8, name, "IL_") or
                    std.mem.startsWith(u8, name, "__dotnet_") or
                    std.mem.startsWith(u8, name, "__cil_") or
                    std.mem.indexOf(u8, name, "__DotNet") != null or
                    std.mem.indexOf(u8, name, "Marshal_") != null or
                    std.mem.indexOf(u8, name, "csharp_exception_personality") != null or
                    std.mem.indexOf(u8, name, "mono_unity_personality") != null)
                {
                    if (source_lang.language != .csharp) {
                        has_multi_lang_hint = true;
                        break;
                    }
                }

                // ── C (Unwind / special sections) ─────────────────
                if (std.mem.eql(u8, name, "_Unwind_Resume") or
                    std.mem.eql(u8, name, "_Unwind_RaiseException") or
                    std.mem.startsWith(u8, name, "__start_") or
                    std.mem.startsWith(u8, name, "__stop_"))
                {
                    if (source_lang.language != .c) {
                        has_multi_lang_hint = true;
                        break;
                    }
                }

                // ── Also check external declarations for multi-language hints ──
                // JNI/Python/Go runtime functions are all external declarations.
                if (c.LLVMIsDeclaration(func) != 0) {
                    // Check JNI external functions
                    if (std.mem.eql(u8, name, "NewGlobalRef") or
                        std.mem.eql(u8, name, "NewLocalRef") or
                        std.mem.eql(u8, name, "NewWeakGlobalRef") or
                        std.mem.eql(u8, name, "DeleteGlobalRef") or
                        std.mem.eql(u8, name, "DeleteLocalRef") or
                        std.mem.eql(u8, name, "DeleteWeakGlobalRef") or
                        std.mem.eql(u8, name, "GetStringUTFChars") or
                        std.mem.eql(u8, name, "ReleaseStringUTFChars") or
                        std.mem.eql(u8, name, "GetStringCritical") or
                        std.mem.eql(u8, name, "ReleaseStringCritical") or
                        std.mem.eql(u8, name, "GetPrimitiveArrayCritical") or
                        std.mem.eql(u8, name, "ReleasePrimitiveArrayCritical") or
                        std.mem.eql(u8, name, "GetByteArrayElements") or
                        std.mem.eql(u8, name, "ReleaseByteArrayElements") or
                        std.mem.eql(u8, name, "CallObjectMethod") or
                        std.mem.eql(u8, name, "CallStaticObjectMethod") or
                        std.mem.eql(u8, name, "FindClass") or
                        std.mem.eql(u8, name, "GetMethodID") or
                        std.mem.eql(u8, name, "GetStaticMethodID") or
                        std.mem.eql(u8, name, "NewObject") or
                        std.mem.eql(u8, name, "NewStringUTF") or
                        std.mem.eql(u8, name, "GetObjectClass"))
                    {
                        has_multi_lang_hint = true;
                        break;
                    }
                    // Check Go CGO external functions
                    if (std.mem.startsWith(u8, name, "_cgo_") or
                        std.mem.startsWith(u8, name, "_Cfunc_"))
                    {
                        has_multi_lang_hint = true;
                        break;
                    }
                    // Check Python C API external functions
                    if (std.mem.startsWith(u8, name, "Py_") or
                        std.mem.startsWith(u8, name, "PyObject_") or
                        std.mem.startsWith(u8, name, "PyInit_"))
                    {
                        has_multi_lang_hint = true;
                        break;
                    }
                    // Check for C standard library functions that indicate C FFI boundary.
                    // When dominant language is not C, extern declarations of these
                    // standard C functions indicate a cross-language interface.
                    if (isStdCFunction(name)) {
                        if (source_lang.language != .c) {
                            has_multi_lang_hint = true;
                            break;
                        }
                    }
                }
            }
        }

        if (!has_multi_lang_hint) {
            if (config.force_analysis) {
                log.info("[Language] Single-language ({s}) but --force-analysis is set, running full analysis\n", .{source_lang_name});
                // fall through to full analysis
            } else {
                log.info("[Language] Single-language ({s}) — OmniScope analyzes cross-language FFI boundaries only, skipping analysis for pure single-language modules\n", .{source_lang_name});
                return;
            }
        }
        // Fall through: detected mixed-language hints
        log.info("[Language] Module appears mixed-language (dominant: {s}), running full analysis\n", .{source_lang_name});
    }

    var result = try pipeline.runModulePipeline(allocator, &loader, config);
    defer pipeline.deinitAnalyzeResult(&result);

    const target_lang = output_formatter.detectTargetLanguage(result.issues);
    const target_lang_name = output_formatter.languageDisplayName(target_lang);

    if (source_lang.language == target_lang) {
        log.info("[Language] Same language ({s}) — no cross-language FFI boundary to analyze\n", .{source_lang_name});
    } else {
        log.info("[Language] Analyzing: {s} --> {s}\n", .{ source_lang_name, target_lang_name });
    }

    try output_formatter.emitOutput(allocator, result.issues, result.func_count, result.time_ms, config, source_lang.language, target_lang);

    if (source_lang.language == target_lang) {
        log.info("[Language] Skipped cross-language analysis: {s} --> {s} (same language)\n", .{
            source_lang_name, target_lang_name,
        });
    } else {
        log.info("[Language] Analysis complete: {d} issues in {s} --> {s} boundary\n", .{
            result.issues.len, source_lang_name, target_lang_name,
        });

        {
            var rust_to_c: usize = 0;
            var c_to_rust: usize = 0;
            var other_boundary: usize = 0;
            for (result.issues) |issue| {
                if (issue.ffi_boundary) |bnd| {
                    if (bnd.caller_language == .rust and bnd.callee_language == .c) {
                        rust_to_c += 1;
                    } else if (bnd.caller_language == .c and bnd.callee_language == .rust) {
                        c_to_rust += 1;
                    } else {
                        other_boundary += 1;
                    }
                }
            }
            if (rust_to_c > 0) log.info("[Language]   rust --> c : {d} issues", .{rust_to_c});
            if (c_to_rust > 0) log.info("[Language]   c --> rust : {d} issues", .{c_to_rust});
            if (other_boundary > 0) log.info("[Language]   other boundary: {d} issues", .{other_boundary});
        }
    }

    if (config.visualize) {
        try generateVisualization(allocator, result.issues, path);
    }
}

/// Check if function name matches a C standard library function.
/// When the dominant language is not C, extern declarations of these
/// standard C functions indicate a C FFI boundary (cross-language interface).
fn isStdCFunction(name: []const u8) bool {
    const c_stdlib_funcs = [_][]const u8{
        // C standard allocator functions
        "malloc",               "calloc",              "realloc",            "free",               "aligned_alloc",       "posix_memalign",
        // macOS specific allocator
        "malloc_create_zone",   "malloc_destroy_zone", "malloc_zone_malloc", "malloc_zone_calloc", "malloc_zone_realloc", "malloc_zone_free",
        "malloc_zone_memalign",
        // mimalloc
        "mi_malloc",           "mi_calloc",          "mi_realloc",         "mi_free",             "mi_malloc_aligned",
        // System calls
        "mmap",                 "munmap",              "mremap",
        // Memory operations
                    "memcpy",             "memmove",             "memset",
        "memcmp",               "strlen",              "strcmp",
        // I/O — common in FFI boundaries
        "printf",              "fprintf",             "sprintf",            "snprintf",
        "fopen",               "fclose",              "fread",              "fwrite",
        "puts",                "fputs",               "getchar",
        // Process control
        "exit",                "abort",               "atexit",
        // String operations
        "strcpy",              "strncpy",             "strcat",             "strncat",
        "strchr",              "strstr",              "strdup",             "strndup",
        // File system
        "open",                "close",               "read",               "write",
        "stat",                "lstat",               "fstat",
        // Time
        "time",                "clock_gettime",       "nanosleep",
        // Other common FFI
        "getenv",              "dlopen",              "dlsym",              "signal",
        "atoi",                "atol",                "strtol",             "strtod",
    };
    for (c_stdlib_funcs) |c_func| {
        if (std.mem.eql(u8, name, c_func)) return true;
    }
    return false;
}

fn generateVisualization(allocator: std.mem.Allocator, issues: []const Issue, path: []const u8) !void {
    const graph_visualizer = @import("./visual/graph_visualizer.zig");
    const GraphIssue = graph_visualizer.GraphIssue;

    var viz = try graph_visualizer.GraphVisualizer.init(allocator);
    defer viz.deinit();

    var graph_issues = try allocator.alloc(GraphIssue, issues.len);
    defer allocator.free(graph_issues);
    for (issues, 0..) |issue, i| {
        graph_issues[i] = .{
            .kind = ffi_precision.issueToGraphKind(issue.kind),
            .message = issue.message,
            .function = issue.location.func,
            .severity = @tagName(issue.severity),
            .confidence = issue.confidence,
            .line = issue.location.line,
        };
    }

    const base_name = std.fs.path.stem(path);
    const out_dir = try std.fmt.allocPrint(allocator, "output/{s}", .{base_name});
    defer allocator.free(out_dir);

    std.fs.cwd().makePath(out_dir) catch |err| {
        log.err("Failed to create {s}: {s}", .{ out_dir, @errorName(err) });
        return;
    };
    const mem_html = try std.fmt.allocPrint(allocator, "{s}/memory.html", .{out_dir});
    defer allocator.free(mem_html);
    const mem_json = try std.fmt.allocPrint(allocator, "{s}/memory.json", .{out_dir});
    defer allocator.free(mem_json);

    log.info("Generating memory graph: {s}\n", .{mem_html});
    viz.exportIssuesHtml(graph_issues, mem_json, mem_html) catch |err| {
        log.info("Warning: Failed to generate visualization: {s}\n", .{@errorName(err)});
    };
}
