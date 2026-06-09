//! Symbol-Centric FFI Boundary Detection Graph
//!
//! Replaces the old module-centric language detection model with
//! per-symbol language classification and cross-language call tracking.
//!
//! Each symbol (function or global variable) carries its own language/ABI
//! classification. Cross-language boundaries emerge at call sites where
//! caller and callee disagree on language.
//!
//! Usage:
//!   var graph = try SymbolGraph.build(allocator, module);
//!   defer graph.deinit();
//!   for (graph.getCrossLangSites()) |site| { ... }
//!   for (graph.getExportSurfaces()) |surface| { ... }

const std = @import("std");
const c = @import("../ir/llvm_raw.zig").c;
const ffi_language_classifier = @import("../pass/analysis/ffi/ffi_language_classifier.zig");

/// Managed ArrayList with stored allocator (Zig 0.15 compat).
pub const ManagedArrayList = std.array_list.Managed;

/// Maximum name length to prevent pathological inputs from consuming memory.
const MAX_NAME_LEN: usize = 4096;

/// Maximum stack frames before we stop unwinding — prevents infinite loops
/// on malformed LLVM constant expressions.
const MAX_CONSTANT_EXPR_DEPTH: u32 = 16;

// ═══════════════════════════════════════════════════════════════
// Data Structures
// ═══════════════════════════════════════════════════════════════

/// Symbol definition kind: defined in this TU vs. declared externally.
pub const SymbolKind = enum(u1) {
    define, // has a body in this translation unit
    declare, // declaration only, defined in another TU or library
};

/// ABI classification determining symbol naming convention and calling convention.
pub const ABIClass = enum(u4) {
    c_abi, // no mangling, plain C linkage
    cxx_itanium, // _Z / _ZN Itanium C++ mangling (GCC, Clang)
    cxx_msvc, // ? name@@ MSVC mangling (MSVC toolchain)
    rust_v0, // _R...   Rust v0 mangling (RFC 2603, Rust 1.37+)
    rust_legacy, // _ZN...17h<hex>E  Rust legacy Itanium mangling
    swift, // _$s...  Swift mangling
    go, // package.Function  Go-style naming
    zig, // zig-specific naming conventions
    builtin, // llvm.* intrinsic (not user code)
    unknown,
};

/// Export visibility based on LLVM linkage type.
pub const ExportClass = enum(u2) {
    not_exported, // internal/private linkage
    weak_exported, // weak/linkonce/available_externally
    exported, // external/dll_export/common linkage
    constructor, // listed in llvm.global_ctors
};

/// Language identifier — superset compatible with FFIBoundary.Language.
pub const LanguageId = enum(u4) {
    c,
    cpp,
    rust,
    zig,
    go,
    java,
    python,
    csharp,
    swift,
    kotlin,
    unknown,
};

/// A single symbol (function or global variable) in the module.
pub const Symbol = struct {
    /// Original symbol name (owned by this struct, freed in deinit).
    name: []const u8,
    /// Human-readable demangled name (nullable, owned, may be null).
    demangled: ?[]const u8,
    /// Definition kind.
    kind: SymbolKind,
    /// ABI class derived from mangling / naming convention.
    abi: ABIClass,
    /// Inferred implementation language.
    lang: LanguageId,
    /// Confidence in language classification (0.0–1.0).
    lang_confidence: f32,
    /// Export visibility.
    exported: ExportClass,
    /// True when kind == .define.
    has_definition: bool,
    /// True when the symbol's address is taken (used as data, not called).
    address_taken: bool,
    /// True when the symbol appears as a function parameter type (callback).
    is_callback_param: bool,
    /// Source file path from DISubprogram debug info (nullable, owned).
    source_file: ?[]const u8,
    /// Raw LLVM value reference (not owned, does not need freeing).
    llvm_value: c.LLVMValueRef,
};

/// A call site within a defined function.
pub const CallSite = struct {
    /// Caller function (must be a define).
    caller: *Symbol,
    /// Called function (may be define or declare).
    callee: *Symbol,
    /// LLVM call or invoke instruction.
    call_inst: c.LLVMValueRef,
    /// True if the call goes through a function pointer.
    is_indirect: bool,
    /// True when caller.lang != callee.lang.
    crosses_language: bool,
    /// True when caller.abi != callee.abi.
    crosses_abi: bool,
};

/// Reason a symbol is considered an FFI export surface.
pub const ExposureReason = enum(u2) {
    c_abi_external_linkage,
    cxx_extern_c,
    constructor_export,
    callback_target,
};

/// Represents a symbol that is externally visible and
/// callable from another language without a local caller.
pub const ExportSurface = struct {
    symbol: *Symbol,
    exposure_reason: ExposureReason,
};

/// Per-symbol classification result from classifySymbol.
pub const SymbolClassification = struct {
    abi: ABIClass,
    lang: LanguageId,
    confidence: f32,
};

/// Caller set for export surface detection.
/// Tracks which symbols are called from within the TU.
pub const CallerSet = struct {
    /// Bitmap or list of callee symbol pointers that have callers.
    /// Using an ArrayList for simplicity; will be small in practice.
    called_set: std.AutoHashMap(*Symbol, void),

    pub fn init(allocator: std.mem.Allocator) CallerSet {
        return .{ .called_set = std.AutoHashMap(*Symbol, void).init(allocator) };
    }

    pub fn deinit(self: *CallerSet) void {
        self.called_set.deinit();
    }

    pub fn markCalled(self: *CallerSet, callee: *Symbol) !void {
        try self.called_set.put(callee, {});
    }

    pub fn hasCaller(self: *CallerSet, callee: *Symbol) bool {
        return self.called_set.contains(callee);
    }
};

// ═══════════════════════════════════════════════════════════════
// SymbolGraph
// ═══════════════════════════════════════════════════════════════

/// The complete symbol graph for an LLVM module.
///
/// Lifecycle:
///   1. Call SymbolGraph.build(allocator, module) to construct.
///   2. Use getCrossLangSites() / getExportSurfaces() to query.
///   3. Call deinit() to free all resources.
///
/// All *Symbol pointers remain valid until deinit().
/// *CallSite pointers from getCrossLangSites() remain valid until deinit().
///
/// Pointer stability guarantee:
///   - call_sites is built in Phase 2 and never modified afterward.
///   - cross_lang_call_indices stores array indices (not pointers) during
///     Phase 2, so they survive potential ArrayList reallocations.
///   - cross_lang_calls (pointers) is resolved in Phase 2b AFTER
///     call_sites is frozen, ensuring all pointers are stable.
pub const SymbolGraph = struct {
    allocator: std.mem.Allocator,
    /// All symbols, keyed by name. Values are owned by this map.
    symbols: std.StringHashMap(Symbol),
    /// All direct and indirect call sites in defined functions.
    call_sites: ManagedArrayList(CallSite),
    /// FFI export surfaces (externally visible, no local caller).
    export_surfaces: ManagedArrayList(ExportSurface),
    /// Index: symbols grouped by language.
    by_language: std.AutoHashMap(LanguageId, ManagedArrayList(*Symbol)),
    /// Index: cross-language call sites (caller-side view).
    /// Stores indices into call_sites. After build() completes, call_sites
    /// is never modified again, so these indices remain valid.
    cross_lang_call_indices: ManagedArrayList(usize),

    /// Resolved cross-language call site pointers.
    /// Built in the final step of build() after call_sites is fully stable.
    /// Safe because no further appends occur to call_sites.
    cross_lang_calls: ManagedArrayList(*CallSite),

    /// Build a SymbolGraph from an LLVM module.
    ///
    /// This function:
    ///   1. Iterates all globals and functions, classifies each symbol.
    ///   2. Iterates all defined functions' instructions to find call sites.
    ///   3. Detects FFI export surfaces.
    ///
    /// Returns an owned SymbolGraph. Caller must call deinit().
    pub fn build(allocator: std.mem.Allocator, module: c.LLVMModuleRef) !SymbolGraph {
        var graph = SymbolGraph{
            .allocator = allocator,
            .symbols = std.StringHashMap(Symbol).init(allocator),
            .call_sites = ManagedArrayList(CallSite).init(allocator),
            .export_surfaces = ManagedArrayList(ExportSurface).init(allocator),
            .by_language = std.AutoHashMap(LanguageId, ManagedArrayList(*Symbol)).init(allocator),
            .cross_lang_call_indices = ManagedArrayList(usize).init(allocator),
            .cross_lang_calls = ManagedArrayList(*CallSite).init(allocator),
        };
        errdefer graph.deinit();

        // ── Phase 1: Collect all symbols ──────────────────────────────
        try collectFunctionSymbols(allocator, module, &graph.symbols);
        try collectGlobalSymbols(allocator, module, &graph.symbols);

        // ── Phase 2: Build call sites from defined functions ──────────
        try buildCallSites(allocator, module, &graph.symbols, &graph.call_sites, &graph.cross_lang_call_indices);

        // ── Phase 2b: Resolve cross-lang indices to stable pointers ──
        // call_sites is now immutable (no more appends), so &call_sites.items[i]
        // pointers are stable until deinit().
        for (graph.cross_lang_call_indices.items) |idx| {
            try graph.cross_lang_calls.append(&graph.call_sites.items[idx]);
        }

        // ── Phase 3: Build by_language index ──────────────────────────
        try buildLanguageIndex(allocator, &graph.symbols, &graph.by_language);

        // ── Phase 4: Export surface detection ─────────────────────────
        try detectExportSurfaces(allocator, &graph.symbols, &graph.call_sites, &graph.export_surfaces);

        return graph;
    }

    /// Free all resources. Must only be called once.
    pub fn deinit(self: *SymbolGraph) void {
        // Free all Symbol-owned strings and demangled/source_file fields.
        var sym_iter = self.symbols.iterator();
        while (sym_iter.next()) |entry| {
            const sym = entry.value_ptr;
            self.allocator.free(sym.name);
            if (sym.demangled) |d| self.allocator.free(d);
            if (sym.source_file) |sf| self.allocator.free(sf);
        }

        // Free all by_language ArrayLists.
        var lang_iter = self.by_language.iterator();
        while (lang_iter.next()) |entry| {
            entry.value_ptr.deinit();
        }

        self.symbols.deinit();
        self.call_sites.deinit();
        self.export_surfaces.deinit();
        self.by_language.deinit();
        self.cross_lang_call_indices.deinit();
        self.cross_lang_calls.deinit();
    }

    /// Return all cross-language call sites.
    pub fn getCrossLangSites(self: *const SymbolGraph) []const *CallSite {
        return self.cross_lang_calls.items;
    }

    /// Return all FFI export surfaces.
    pub fn getExportSurfaces(self: *const SymbolGraph) []const ExportSurface {
        return self.export_surfaces.items;
    }
};

// ═══════════════════════════════════════════════════════════════
// classifySymbol
// ═══════════════════════════════════════════════════════════════

/// Classify a single symbol's ABI and language based on its name and LLVM metadata.
///
/// Decision order:
///   1. Mangling-based ABI detection (name prefix patterns).
///   2. LLVM intrinsic detection (llvm.* prefix).
///   3. Debug info fallback (DISubprogram → DIFile extension).
///   4. Name-based heuristic fallback (via ffi_language_classifier).
///
/// Returns a SymbolClassification with abi, lang, and confidence.
pub fn classifySymbol(name: []const u8, llvm_value: c.LLVMValueRef, module: c.LLVMModuleRef) SymbolClassification {
    _ = module;

    // Clamp name length to avoid pathological inputs.
    if (name.len == 0 or name.len > MAX_NAME_LEN) {
        return .{ .abi = .unknown, .lang = .unknown, .confidence = 0.0 };
    }

    // Rule: llvm.* prefix → builtin, not user code, confidence = 0.
    if (std.mem.startsWith(u8, name, "llvm.")) {
        return .{ .abi = .builtin, .lang = .unknown, .confidence = 0.0 };
    }

    // ── Mangling-based ABI detection (rules from plan §2) ──────

    // Rule: _R prefix → Rust v0 mangling (RFC 2603)
    if (name.len > 2 and name[0] == '_' and name[1] == 'R') {
        return .{ .abi = .rust_v0, .lang = .rust, .confidence = 0.99 };
    }

    // Rule: _ZN + 17h<16 hex>E suffix → Rust legacy mangling
    // Pattern: _ZN<any>17h[0-9a-f]{16}E
    if (name.len > 3 and name[0] == '_' and name[1] == 'Z' and name[2] == 'N') {
        if (hasRustLegacySuffix(name)) {
            return .{ .abi = .rust_legacy, .lang = .rust, .confidence = 0.95 };
        }
        // _ZN (non-Rust-legacy) → C++ Itanium
        return .{ .abi = .cxx_itanium, .lang = .cpp, .confidence = 0.95 };
    }

    // Rule: _Z (not _ZN) prefix → C++ Itanium mangling
    if (name.len > 2 and name[0] == '_' and name[1] == 'Z' and name[2] != 'N') {
        return .{ .abi = .cxx_itanium, .lang = .cpp, .confidence = 0.95 };
    }

    // Rule: ? prefix → MSVC mangling
    if (name.len > 0 and name[0] == '?') {
        return .{ .abi = .cxx_msvc, .lang = .cpp, .confidence = 0.95 };
    }

    // Rule: _$s prefix → Swift mangling
    if (name.len > 3 and name[0] == '_' and name[1] == '$' and name[2] == 's') {
        return .{ .abi = .swift, .lang = .swift, .confidence = 0.99 };
    }

    // Rule: path-style with '.' separator → Go
    if (isGoStyleName(name)) {
        return .{ .abi = .go, .lang = .go, .confidence = 0.95 };
    }

    // ── Default: c_abi with debug info / heuristic fallback ──

    // Try debug info first: DISubprogram → DIFile extension.
    // LLVMGetSubprogram is only valid for function values, not globals.
    if (llvm_value != null and c.LLVMIsAFunction(llvm_value) != null) {
        // Only functions have DISubprogram; globals won't match.
        const subprogram = c.LLVMGetSubprogram(llvm_value);
        if (subprogram != null) {
            const file_md = c.LLVMDIScopeGetFile(subprogram);
            if (file_md != null) {
                var file_len: c_uint = 0;
                const file_ptr = c.LLVMDIFileGetFilename(file_md, &file_len);
                if (file_ptr != null and file_len > 0) {
                    const filename = file_ptr[0..file_len];
                    if (std.mem.endsWith(u8, filename, ".zig")) {
                        return .{ .abi = .c_abi, .lang = .zig, .confidence = 0.85 };
                    }
                    if (std.mem.endsWith(u8, filename, ".rs")) {
                        return .{ .abi = .c_abi, .lang = .rust, .confidence = 0.85 };
                    }
                    if (std.mem.endsWith(u8, filename, ".go")) {
                        return .{ .abi = .c_abi, .lang = .go, .confidence = 0.85 };
                    }
                    if (std.mem.endsWith(u8, filename, ".c")) {
                        return .{ .abi = .c_abi, .lang = .c, .confidence = 0.85 };
                    }
                    if (std.mem.endsWith(u8, filename, ".cpp") or
                        std.mem.endsWith(u8, filename, ".cc") or
                        std.mem.endsWith(u8, filename, ".cxx") or
                        std.mem.endsWith(u8, filename, ".hpp") or
                        std.mem.endsWith(u8, filename, ".h"))
                    {
                        return .{ .abi = .c_abi, .lang = .cpp, .confidence = 0.85 };
                    }
                }
            }
        }
    }

    // Fallback: use name-based heuristic via ffi_language_classifier.
    const lang = ffi_language_classifier.identifyCalleeLanguage(name);

    // Map Language back to LanguageId (they share the same tag names).
    const lang_id: LanguageId = switch (lang) {
        .c => .c,
        .cpp => .cpp,
        .rust => .rust,
        .zig => .zig,
        .go => .go,
        .java => .java,
        .python => .python,
        .csharp => .csharp,
        .unknown => .unknown,
    };

    // Confidence: lower for heuristic fallback vs. mangling detection.
    const confidence: f32 = if (lang_id != .unknown) 0.7 else 0.0;

    return .{ .abi = .c_abi, .lang = lang_id, .confidence = confidence };
}

// ═══════════════════════════════════════════════════════════════
// Internal Helpers
// ═══════════════════════════════════════════════════════════════

/// Check if a _ZN-prefixed name has the Rust legacy hash suffix (17h<hex>E).
fn hasRustLegacySuffix(name: []const u8) bool {
    // Pattern: ...17h[0-9a-f]{16}E at the end of the name.
    const suffix = "17h";
    const hex_len: usize = 16;

    const suffix_pos = std.mem.lastIndexOf(u8, name, suffix) orelse return false;
    if (suffix_pos + suffix.len + hex_len + 1 != name.len) return false;

    // Verify 'E' at the end.
    if (name[name.len - 1] != 'E') return false;

    // Verify 16 hex digits between 'h' and 'E'.
    const hex_start = suffix_pos + suffix.len;
    for (name[hex_start .. hex_start + hex_len]) |ch| {
        const is_hex = switch (ch) {
            '0'...'9', 'a'...'f', 'A'...'F' => true,
            else => false,
        };
        if (!is_hex) return false;
    }

    return true;
}

/// Check if the name follows Go-style path naming (package.Function).
///
/// Heuristic: name contains at least one '.' and the segment before the
/// first '.' is all lowercase (a Go package name). Zig also uses '.'
/// but Zig uses PascalCase for the first segment (module/type name).
fn isGoStyleName(name: []const u8) bool {
    // Must contain at least one '.'.
    const dot_pos = std.mem.indexOf(u8, name, ".") orelse return false;
    if (dot_pos == 0) return false;

    // First segment must be all lowercase (Go package name).
    const first_seg = name[0..dot_pos];
    for (first_seg) |ch| {
        if (ch >= 'A' and ch <= 'Z') return false; // PascalCase → likely Zig
    }

    // Must not have obvious Zig indicators.
    if (std.mem.indexOf(u8, name, "@") != null) return false;

    // Must not have obvious Rust or C++ indicators.
    if (std.mem.startsWith(u8, name, "_")) return false;

    return true;
}

/// Get the source file from a function's debug info, if available.
/// Returns null if no debug info or if the value is not a function.
fn getSourceFile(allocator: std.mem.Allocator, llvm_value: c.LLVMValueRef) !?[]const u8 {
    const subprogram = c.LLVMGetSubprogram(llvm_value);
    if (subprogram == null) return null;

    const file_md = c.LLVMDIScopeGetFile(subprogram);
    if (file_md == null) return null;

    var file_len: c_uint = 0;
    const file_ptr = c.LLVMDIFileGetFilename(file_md, &file_len);
    if (file_ptr == null or file_len == 0) return null;

    return try allocator.dupe(u8, file_ptr[0..file_len]);
}

/// Classify LLVM linkage to ExportClass.
fn classifyLinkage(llvm_value: c.LLVMValueRef) ExportClass {
    const linkage = c.LLVMGetLinkage(llvm_value);
    return switch (linkage) {
        c.LLVMExternalLinkage => .exported,
        c.LLVMAvailableExternallyLinkage => .weak_exported,
        c.LLVMLinkOnceAnyLinkage => .weak_exported,
        c.LLVMLinkOnceODRLinkage => .weak_exported,
        c.LLVMWeakAnyLinkage => .weak_exported,
        c.LLVMWeakODRLinkage => .weak_exported,
        c.LLVMAppendingLinkage => .exported,
        c.LLVMInternalLinkage => .not_exported,
        c.LLVMPrivateLinkage => .not_exported,
        c.LLVMDLLImportLinkage => .exported,
        c.LLVMDLLExportLinkage => .exported,
        c.LLVMExternalWeakLinkage => .weak_exported,
        c.LLVMGhostLinkage => .weak_exported,
        c.LLVMCommonLinkage => .exported,
        c.LLVMLinkerPrivateLinkage => .not_exported,
        c.LLVMLinkerPrivateWeakLinkage => .weak_exported,
        else => .not_exported,
    };
}

// ═══════════════════════════════════════════════════════════════
// Symbol Collection Phases
// ═══════════════════════════════════════════════════════════════

/// Collect all function symbols from the module.
fn collectFunctionSymbols(
    allocator: std.mem.Allocator,
    module: c.LLVMModuleRef,
    symbols: *std.StringHashMap(Symbol),
) !void {
    var func = c.LLVMGetFirstFunction(module);
    while (func != null) : (func = c.LLVMGetNextFunction(func)) {
        const name_ptr = c.LLVMGetValueName(func);
        if (name_ptr == null) continue;
        const name = std.mem.span(name_ptr);
        if (name.len == 0 or name.len > MAX_NAME_LEN) continue;

        const name_owned = try allocator.dupe(u8, name);
        errdefer allocator.free(name_owned);

        const is_decl = c.LLVMIsDeclaration(func) != 0;

        // Classify the symbol.
        const classification = classifySymbol(name, func, module);

        // Get debug info source file.
        const source_file = try getSourceFile(allocator, func);
        errdefer if (source_file) |sf| allocator.free(sf);

        // Demangling for known mangled names.
        const demangled = try demangleIfKnown(allocator, name, classification.abi);
        errdefer if (demangled) |d| allocator.free(d);

        // Address-taken check: iterate uses.
        const address_taken = checkAddressTaken(func);

        const sym = Symbol{
            .name = name_owned,
            .demangled = demangled,
            .kind = if (is_decl) .declare else .define,
            .abi = classification.abi,
            .lang = classification.lang,
            .lang_confidence = classification.confidence,
            .exported = if (is_decl) .not_exported else classifyLinkage(func),
            .has_definition = !is_decl,
            .address_taken = address_taken,
            .is_callback_param = false, // requires type analysis; deferred.
            .source_file = source_file,
            .llvm_value = func,
        };

        try symbols.put(name_owned, sym);
    }
}

/// Collect all global variable symbols from the module.
fn collectGlobalSymbols(
    allocator: std.mem.Allocator,
    module: c.LLVMModuleRef,
    symbols: *std.StringHashMap(Symbol),
) !void {
    var global = c.LLVMGetFirstGlobal(module);
    while (global != null) : (global = c.LLVMGetNextGlobal(global)) {
        const name_ptr = c.LLVMGetValueName(global);
        if (name_ptr == null) continue;
        const name = std.mem.span(name_ptr);
        if (name.len == 0 or name.len > MAX_NAME_LEN) continue;

        const name_owned = try allocator.dupe(u8, name);
        errdefer allocator.free(name_owned);

        const is_decl = c.LLVMIsDeclaration(global) != 0;

        // Classify the symbol.
        const classification = classifySymbol(name, global, module);

        const sym = Symbol{
            .name = name_owned,
            .demangled = null,
            .kind = if (is_decl) .declare else .define,
            .abi = classification.abi,
            .lang = classification.lang,
            .lang_confidence = classification.confidence,
            .exported = classifyLinkage(global),
            .has_definition = !is_decl,
            .address_taken = false,
            .is_callback_param = false,
            .source_file = null,
            .llvm_value = global,
        };

        try symbols.put(name_owned, sym);
    }
}

/// Check if a function's address is taken by examining its uses.
/// Returns true if any use is not a direct call/invoke instruction.
fn checkAddressTaken(func: c.LLVMValueRef) bool {
    var use_ref = c.LLVMGetFirstUse(func);
    while (use_ref != null) : (use_ref = c.LLVMGetNextUse(use_ref)) {
        const user = c.LLVMGetUser(use_ref);
        if (user == null) continue;

        const opcode = c.LLVMGetInstructionOpcode(user);
        // If the user is not a call or invoke, the address is used as data.
        if (opcode != c.LLVMCall and opcode != c.LLVMInvoke) {
            return true;
        }
    }
    return false;
}

/// Attempt to demangle a name based on its ABI class.
/// Returns null if demangling is not applicable or fails.
fn demangleIfKnown(allocator: std.mem.Allocator, name: []const u8, abi: ABIClass) !?[]const u8 {
    return switch (abi) {
        .cxx_itanium => try demangleItanium(allocator, name),
        .rust_v0, .rust_legacy => try ffi_language_classifier.demangleRustName(allocator, name),
        .cxx_msvc => try ffi_language_classifier.demangleMsvcName(allocator, name),
        else => null,
    };
}

/// Simple Itanium demangler: extracts the first identifier after _Z.
/// Full demangling is complex; this provides a best-effort readable form.
fn demangleItanium(allocator: std.mem.Allocator, name: []const u8) !?[]const u8 {
    if (name.len < 3 or name[0] != '_' or name[1] != 'Z') return null;

    var pos: usize = 2;

    // Skip _ZN prefix (nested name).
    if (name.len > 3 and name[2] == 'N') {
        pos = 3;
        // Skip length-encoded identifiers until 'E'.
        while (pos < name.len and name[pos] != 'E') {
            if (name[pos] < '0' or name[pos] > '9') break;
            var len: usize = 0;
            while (pos < name.len and name[pos] >= '0' and name[pos] <= '9') : (pos += 1) {
                len = len * 10 + @as(usize, name[pos] - '0');
            }
            if (len == 0 or pos + len > name.len) return null;
            if (len > 50) return null;

            const ident = name[pos .. pos + len];
            pos += len;

            // Try to produce "ns::name" form.
            if (pos < name.len and name[pos] == 'E') {
                return try allocator.dupe(u8, ident);
            }
            // If there's more after this, we'd need full parsing.
            // For simplicity, return the last identifier.
        }
    }

    // Plain _Z: try to extract length-encoded function name.
    if (pos < name.len and name[pos] >= '0' and name[pos] <= '9') {
        var len: usize = 0;
        while (pos < name.len and name[pos] >= '0' and name[pos] <= '9') : (pos += 1) {
            len = len * 10 + @as(usize, name[pos] - '0');
        }
        if (len > 0 and pos + len <= name.len and len <= 50) {
            return try allocator.dupe(u8, name[pos .. pos + len]);
        }
    }

    return null;
}

// ═══════════════════════════════════════════════════════════════
// Call Site Construction
// ═══════════════════════════════════════════════════════════════

/// Build call sites by iterating all defined functions' instructions.
/// Uses a two-pass approach: first collect all call sites, then
/// populate cross_lang_calls indices to avoid dangling pointers from
/// ManagedArrayList reallocation.
fn buildCallSites(
    allocator: std.mem.Allocator,
    module: c.LLVMModuleRef,
    symbols: *const std.StringHashMap(Symbol),
    call_sites: *ManagedArrayList(CallSite),
    cross_lang_indices: *ManagedArrayList(usize),
) !void {
    _ = allocator;

    var func = c.LLVMGetFirstFunction(module);
    while (func != null) : (func = c.LLVMGetNextFunction(func)) {
        // Only defined functions have instructions.
        if (c.LLVMIsDeclaration(func) != 0) continue;

        const caller_name_ptr = c.LLVMGetValueName(func);
        if (caller_name_ptr == null) continue;
        const caller_name = std.mem.span(caller_name_ptr);
        const caller = symbols.getPtr(caller_name) orelse continue;

        // Iterate basic blocks.
        var bb = c.LLVMGetFirstBasicBlock(func);
        while (bb != null) : (bb = c.LLVMGetNextBasicBlock(bb)) {
            var inst = c.LLVMGetFirstInstruction(bb);
            while (inst != null) : (inst = c.LLVMGetNextInstruction(inst)) {
                const opcode = c.LLVMGetInstructionOpcode(inst);

                // LLVMCall = 56, LLVMInvoke = 55
                if (opcode != c.LLVMCall and opcode != c.LLVMInvoke) continue;

                try processCallInstruction(caller, inst, symbols, call_sites);
            }
        }
    }

    // Second pass: collect cross-language call site indices.
    // Storing indices (not pointers) is safe even if call_sites reallocates
    // during the first pass — indices remain valid. The pointer resolution
    // happens in build() after this function returns, when call_sites is
    // guaranteed stable.
    for (call_sites.items, 0..) |*site, idx| {
        if (site.crosses_language or site.crosses_abi) {
            try cross_lang_indices.append(idx);
        }
    }
}

/// Process a single call/invoke instruction.
/// Does NOT track cross-language calls directly — that is done in a second
/// pass by buildCallSites to avoid dangling pointer issues.
fn processCallInstruction(
    caller: *Symbol,
    call_inst: c.LLVMValueRef,
    symbols: *const std.StringHashMap(Symbol),
    call_sites: *ManagedArrayList(CallSite),
) !void {
    const called_value = c.LLVMGetCalledValue(call_inst);
    if (called_value == null) return;

    // Determine if this is an indirect call.
    const is_indirect = c.LLVMIsAFunction(called_value) == null;

    // Resolve the called function name.
    const callee_name = resolveCalleeName(called_value) orelse return;
    if (callee_name.len == 0 or callee_name.len > MAX_NAME_LEN) return;

    // Look up the callee in symbols.
    const callee = symbols.getPtr(callee_name) orelse return;

    const crosses_language = caller.lang != callee.lang;
    const crosses_abi = caller.abi != callee.abi;

    const site = CallSite{
        .caller = caller,
        .callee = callee,
        .call_inst = call_inst,
        .is_indirect = is_indirect,
        .crosses_language = crosses_language,
        .crosses_abi = crosses_abi,
    };

    try call_sites.append(site);
}

/// Resolve the callee name from a called value.
/// Handles direct function calls and constant expression wrappers.
fn resolveCalleeName(called_value: c.LLVMValueRef) ?[]const u8 {
    // Direct function call.
    if (c.LLVMIsAFunction(called_value)) |func| {
        const name_ptr = c.LLVMGetValueName(func);
        if (name_ptr == null) return null;
        const name = std.mem.span(name_ptr);
        if (name.len == 0) return null;
        return name;
    }

    // Try constant expression unfolding (e.g., bitcast of function pointer).
    if (c.LLVMIsAConstantExpr(called_value)) |cexpr| {
        return resolveConstantExprCallee(cexpr, 0);
    }

    // Try global variable containing a function pointer.
    if (c.LLVMIsAGlobalVariable(called_value)) |gv| {
        const initializer = c.LLVMGetInitializer(gv);
        if (initializer != null) {
            if (c.LLVMIsAFunction(initializer)) |func| {
                const name_ptr = c.LLVMGetValueName(func);
                if (name_ptr == null) return null;
                return std.mem.span(name_ptr);
            }
        }
    }

    return null;
}

/// Unfold constant expressions to find an underlying function reference.
fn resolveConstantExprCallee(cexpr: c.LLVMValueRef, depth: u32) ?[]const u8 {
    if (depth > MAX_CONSTANT_EXPR_DEPTH) return null;

    const num_ops: usize = @intCast(c.LLVMGetNumOperands(cexpr));
    for (0..num_ops) |i| {
        const op = c.LLVMGetOperand(cexpr, @as(c_uint, @intCast(i)));
        if (op == null) continue;

        if (c.LLVMIsAFunction(op)) |func| {
            const name_ptr = c.LLVMGetValueName(func);
            if (name_ptr == null) return null;
            return std.mem.span(name_ptr);
        }

        if (c.LLVMIsAConstantExpr(op)) |child_cexpr| {
            if (resolveConstantExprCallee(child_cexpr, depth + 1)) |name| {
                return name;
            }
        }
    }

    return null;
}

// ═══════════════════════════════════════════════════════════════
// Language Index
// ═══════════════════════════════════════════════════════════════

/// Build the by_language index: group symbol pointers by language.
fn buildLanguageIndex(
    allocator: std.mem.Allocator,
    symbols: *const std.StringHashMap(Symbol),
    by_language: *std.AutoHashMap(LanguageId, ManagedArrayList(*Symbol)),
) !void {
    _ = allocator;

    var iter = symbols.iterator();
    while (iter.next()) |entry| {
        const sym = entry.value_ptr;
        const lang = sym.lang;

        var list = try by_language.getOrPut(lang);
        if (!list.found_existing) {
            list.value_ptr.* = ManagedArrayList(*Symbol).init(symbols.allocator);
        }
        try list.value_ptr.append(sym);
    }
}

// ═══════════════════════════════════════════════════════════════
// Export Surface Detection
// ═══════════════════════════════════════════════════════════════

/// Detect FFI export surfaces: defined symbols that are externally visible
/// and have no local caller, or are callback targets.
fn detectExportSurfaces(
    allocator: std.mem.Allocator,
    symbols: *const std.StringHashMap(Symbol),
    call_sites: *const ManagedArrayList(CallSite),
    export_surfaces: *ManagedArrayList(ExportSurface),
) !void {
    _ = allocator;

    // Build a set of all callees that have local callers.
    var caller_set = std.AutoHashMap(*const Symbol, void).init(symbols.allocator);
    defer caller_set.deinit();

    for (call_sites.items) |*site| {
        try caller_set.put(site.callee, {});
    }

    // Iterate all symbols to find export surfaces.
    var iter = symbols.iterator();
    while (iter.next()) |entry| {
        const sym = entry.value_ptr;

        // Skip declarations and builtins.
        if (sym.kind != .define) continue;
        if (sym.abi == .builtin) continue;

        // Check if this symbol is externally visible.
        const is_exported = switch (sym.exported) {
            .exported, .weak_exported, .constructor => true,
            .not_exported => false,
        };
        if (!is_exported) continue;

        // Check ABI: external ABIs that another language can call.
        const has_external_abi = switch (sym.abi) {
            .c_abi, .cxx_itanium, .cxx_msvc, .rust_v0, .rust_legacy, .swift, .go, .zig => true,
            .builtin, .unknown => false,
        };
        if (!has_external_abi) continue;

        // Check if the symbol has no local caller.
        const no_local_caller = !caller_set.contains(sym);

        // ── Exposure reason determination ──

        // Case 1: Constructor export.
        if (sym.exported == .constructor) {
            try export_surfaces.append(.{
                .symbol = sym,
                .exposure_reason = .constructor_export,
            });
            continue;
        }

        // Case 2: C ABI external linkage with no local caller → export surface.
        if (no_local_caller) {
            const reason: ExposureReason = switch (sym.abi) {
                .c_abi => .c_abi_external_linkage,
                .cxx_itanium, .cxx_msvc => .cxx_extern_c,
                else => .c_abi_external_linkage,
            };
            try export_surfaces.append(.{
                .symbol = sym,
                .exposure_reason = reason,
            });
            continue;
        }

        // Case 3: Callback target — address is taken and the symbol
        // is passed as a function pointer parameter to a registration function.
        // Simple heuristic: if address is taken and exported, it's a callback.
        if (sym.address_taken and sym.exported == .exported) {
            try export_surfaces.append(.{
                .symbol = sym,
                .exposure_reason = .callback_target,
            });
            continue;
        }
    }
}

// ═══════════════════════════════════════════════════════════════
// Tests
// ═══════════════════════════════════════════════════════════════

test "classifySymbol — Rust v0 mangling (_R prefix)" {
    const classification = classifySymbol("_RNvCs1234_7mycrate8myfunc", null, null);
    try std.testing.expectEqual(ABIClass.rust_v0, classification.abi);
    try std.testing.expectEqual(LanguageId.rust, classification.lang);
    try std.testing.expect(classification.confidence > 0.9);
}

test "classifySymbol — Rust legacy mangling (_ZN + 17h<hash>E)" {
    const classification = classifySymbol("_ZN4core3ptr5dangle17h1234567890abcdefE", null, null);
    try std.testing.expectEqual(ABIClass.rust_legacy, classification.abi);
    try std.testing.expectEqual(LanguageId.rust, classification.lang);
    try std.testing.expect(classification.confidence > 0.9);
}

test "classifySymbol — C++ Itanium (_ZN without Rust hash)" {
    const classification = classifySymbol("_ZN8cpp_hash4HashEPKhmPh", null, null);
    try std.testing.expectEqual(ABIClass.cxx_itanium, classification.abi);
    try std.testing.expectEqual(LanguageId.cpp, classification.lang);
    try std.testing.expect(classification.confidence > 0.9);
}

test "classifySymbol — C++ Itanium (_Z plain)" {
    const classification = classifySymbol("_Z3fooi", null, null);
    try std.testing.expectEqual(ABIClass.cxx_itanium, classification.abi);
    try std.testing.expectEqual(LanguageId.cpp, classification.lang);
    try std.testing.expect(classification.confidence > 0.9);
}

test "classifySymbol — MSVC mangling (? prefix)" {
    const classification = classifySymbol("?square@@YAHH@Z", null, null);
    try std.testing.expectEqual(ABIClass.cxx_msvc, classification.abi);
    try std.testing.expectEqual(LanguageId.cpp, classification.lang);
    try std.testing.expect(classification.confidence > 0.9);
}

test "classifySymbol — Swift mangling (_$s prefix)" {
    const classification = classifySymbol("_$s12swift_module08myFunctionyyF", null, null);
    try std.testing.expectEqual(ABIClass.swift, classification.abi);
    try std.testing.expectEqual(LanguageId.swift, classification.lang);
    try std.testing.expect(classification.confidence > 0.9);
}

test "classifySymbol — Go style (path.with.dots)" {
    const classification = classifySymbol("net/http.(*Server).ServeHTTP", null, null);
    try std.testing.expectEqual(ABIClass.go, classification.abi);
    try std.testing.expectEqual(LanguageId.go, classification.lang);
    try std.testing.expect(classification.confidence > 0.9);
}

test "classifySymbol — Go style (package.Function)" {
    const classification = classifySymbol("main.main", null, null);
    try std.testing.expectEqual(ABIClass.go, classification.abi);
    try std.testing.expectEqual(LanguageId.go, classification.lang);
    try std.testing.expect(classification.confidence > 0.9);
}

test "classifySymbol — LLVM builtin" {
    const classification = classifySymbol("llvm.vector.reduce.add", null, null);
    try std.testing.expectEqual(ABIClass.builtin, classification.abi);
    try std.testing.expect(classification.confidence == 0.0);
}

test "classifySymbol — plain C (fallback)" {
    const classification = classifySymbol("ffi_make_token", null, null);
    try std.testing.expectEqual(ABIClass.c_abi, classification.abi);
    // Language is C via classification fallback.
    try std.testing.expect(classification.confidence > 0.0);
}

test "classifySymbol — empty name" {
    const classification = classifySymbol("", null, null);
    try std.testing.expectEqual(ABIClass.unknown, classification.abi);
    try std.testing.expectEqual(LanguageId.unknown, classification.lang);
}

test "classifySymbol — Zig style (not matched as Go)" {
    // Zig uses PascalCase-first segments, so this should NOT be Go.
    const classification = classifySymbol("Io.Writer.defaultFlush", null, null);
    // Falls through to c_abi with heuristic fallback since "Io" starts with uppercase.
    try std.testing.expectEqual(ABIClass.c_abi, classification.abi);
}

test "hasRustLegacySuffix — positive cases" {
    try std.testing.expect(hasRustLegacySuffix("_ZN4core3ptr5dangle17h1234567890abcdefE"));
    try std.testing.expect(hasRustLegacySuffix("_ZN3std2io5stdio6stdout17hdeadbeefcafebabeE"));
}

test "hasRustLegacySuffix — negative cases" {
    // C++ Itanium _ZN without hash suffix.
    try std.testing.expect(!hasRustLegacySuffix("_ZN8cpp_hash4HashEPKhmPh"));
    // Wrong hash length.
    try std.testing.expect(!hasRustLegacySuffix("_ZN4core3ptr5dangle17h1234E"));
    // No suffix at all.
    try std.testing.expect(!hasRustLegacySuffix("_ZN3std3io5printE"));
}
