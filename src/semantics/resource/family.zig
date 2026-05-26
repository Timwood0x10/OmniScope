//! Resource Family — Core Type Definitions for Cross-Language Allocator Classification.
//!
//! Replaces language-based alloc/free matching with family-based matching.
//! A "family" is a semantic group of allocator/deallocator pairs that share
//! the same underlying memory management mechanism, regardless of source language.
//!
//! Key insight: `PyObject_New + PyObject_Free` are the same family even though
//! both are "C" language. Conversely, `malloc + delete[]` are different families
//! even though both are "C/C++". Language is a hint; family is the ground truth.
//!
//! See also: family_registry.zig (builtin table), improve.md (design rationale).

const std = @import("std");

// ============================================================================
// FamilyId — Compact integer identifier for resource families
// ============================================================================

/// Compact integer ID for a resource family. Uses small integers to avoid
/// string storage on hot paths. Value 0 is reserved as "unknown/invalid".
pub const FamilyId = enum(u16) {
    /// Unknown or unclassified family. Must not be used as a valid match.
    invalid = 0,

    // --- C Standard Library ---
    /// malloc / calloc / realloc ↔ free
    c_heap = 1,
    /// mmap / munmap (POSIX memory mapping)
    c_mmap = 2,
    /// POSIX memalign / aligned_alloc / free
    c_aligned = 3,

    // --- C++ Runtime ---
    /// operator new / _Znwm / _Znwj ↔ operator delete / _ZdlPv
    cpp_new_scalar = 10,
    /// operator new[] / _Znam / _Znaj ↔ operator delete[] / _ZdaPv
    cpp_new_array = 11,

    // --- Rust Global Allocator ---
    /// __rust_alloc / __rust_alloc_zeroed ↔ __rust_dealloc
    rust_global = 20,
    /// Rust Box::into_raw / Box::from_raw (ownership transfer pair)
    rust_box = 21,

    // --- Python C API ---
    /// PyObject_New / PyObject_NewVar / PyType_GenericAlloc ↔ PyObject_Del / PyObject_Free
    python_object = 30,
    /// PyMem_Malloc / PyMem_Calloc / PyMem_Realloc ↔ PyMem_Free
    python_mem = 31,
    /// PyMem_RawMalloc / PyMem_RawCalloc / PyMem_RawRealloc ↔ PyMem_RawFree
    python_mem_raw = 32,

    // --- Java/JNI ---
    /// NewLocalRef ↔ DeleteLocalRef
    java_local_ref = 40,
    /// NewGlobalRef ↔ DeleteGlobalRef
    java_global_ref = 41,

    // --- C#/.NET Interop ---
    /// Marshal.AllocHGlobal ↔ Marshal.FreeHGlobal
    csharp_hglobal = 50,
    /// CoTaskMemAlloc ↔ CoTaskMemFree
    csharp_cotask = 51,

    // --- Go Runtime ---
    /// runtime.mallocgc (GC-managed, no manual free)
    go_gc = 60,

    // --- Zig Allocator (abstract) ---
    /// Zig allocator vtable .alloc / .free chain (abstract, weak match)
    zig_allocator = 70,

    /// Sentinel value for iteration bounds. Not a valid family.
    sentinel = 255,
};

// ============================================================================
// FamilyKind — Semantic category of a resource family
// ============================================================================

/// High-level classification of what kind of resource a family manages.
/// Used for policy decisions (e.g., GC families don't expect manual free).
pub const FamilyKind = enum(u8) {
    /// Standard heap memory (malloc/free, new/delete, etc.)
    heap_memory,
    /// C++ object with constructor/destructor semantics.
    cpp_object,
    /// Reference-counted object (Python PyObject, ARC, COM).
    refcounted_object,
    /// Garbage-collected memory (Go, Java heap, etc.).
    gc_managed,
    /// JNI local/global reference (Java native interop).
    jni_ref,
    /// OS-level handle (file descriptor, socket, etc.).
    handle,
    /// Arena/region allocator (bounded lifetime).
    arena,
    /// Memory-mapped region (mmap/munmap).
    mapped_memory,
    /// Unknown or unclassified.
    unknown,
};

// ============================================================================
// LifetimeDomain — How resources in this family are managed
// ============================================================================

/// Describes the lifetime management strategy for a resource family.
/// Determines what kinds of release operations are valid and expected.
pub const LifetimeDomain = enum(u8) {
    /// Manual alloc/free pairs (C heap, C++ new/delete). Caller must free.
    manual,
    /// Reference counting (Py_INCREF/Py_DECREF, ARC retain/release).
    refcounted,
    /// Garbage collected (Go runtime, Java GC). No explicit free expected.
    gc,
    /// Process lifetime (static storage, process-global state).
    process_static,
    /// Arena-scoped (destroyed when arena is deallocated).
    arena_scoped,
    /// Unknown lifetime domain.
    unknown,
};

// ============================================================================
// ResourceOpKind — What operation does a function perform on a resource?
// ============================================================================

/// Classifies the semantic effect of a function call on resource ownership.
pub const ResourceOpKind = enum(u8) {
    /// Allocates new resource (malloc, new, PyObject_New, ...).
    acquire,
    /// Releases/frees resource (free, delete, PyObject_Del, ...).
    release,
    /// Increments reference count without taking ownership (Py_INCREF, retain).
    retain,
    /// Borrows pointer without ownership change (as_ptr, borrow).
    borrow,
    /// Transfers ownership to caller (returns_owned, out-param init).
    transfer,
    /// Conditionally releases (Py_DECREF, Arc::drop — may or may not free).
    conditional_release,
    /// Unknown operation.
    unknown,
};

// ============================================================================
// FamilyMatchResult — Result of comparing alloc and release families
// ============================================================================

/// Result of comparing an allocation family with a release family.
/// Drives the cross-free validity decision in Phase 3.
pub const FamilyMatchResult = enum(u8) {
    /// Same family: alloc and release belong to identical family.
    /// This is always a valid release (e.g., malloc + free).
    same_family,
    /// Compatible families: different but semantically compatible release.
    /// E.g., PyMem_Malloc (python_mem) + PyMem_Free (python_mem_raw) — both CPython.
    compatible_family,
    /// Mismatch: alloc and release are from incompatible families.
    /// This is a potential bug (e.g., malloc + delete[], __rust_alloc + free).
    mismatch,
    /// Allocation family is unknown (could not classify the allocator).
    unknown_alloc,
    /// Release family is unknown (could not classify the releaser).
    unknown_release,
    /// Both sides unknown.
    unknown_both,
};

// ============================================================================
// EvidenceSource — Where did this family classification come from?
// ============================================================================

/// Provenance of a family classification decision. Every family assignment
/// must carry evidence so that false positives can be audited and explained.
pub const EvidenceSource = enum(u8) {
    /// Built into the registry as a known allocator/deallocator pair.
    builtin_registry,
    /// Matched by name pattern (prefix/suffix/mangling heuristic).
    name_pattern,
    /// Inferred from structural IR analysis (destructor shape, etc.).
    structural_inference,
    /// Provided by user via project model file (--semantic-model).
    project_model,
    /// Fallback heuristic when no better classification available.
    fallback_heuristic,
    /// Completely unknown — no evidence available.
    unknown,
};

// ============================================================================
// FamilyOp — A single allocator/deallocator operation record
// ============================================================================

/// Describes a single operation (acquire/release/retain) within a family.
/// Stored in the registry and returned by lookup queries.
pub const FamilyOp = struct {
    /// Which family this operation belongs to.
    family: FamilyId,
    /// What kind of operation this is (acquire, release, retain, ...).
    op_kind: ResourceOpKind,
    /// The canonical function name for this operation (e.g., "malloc", "free").
    canonical_name: []const u8,
    /// Alternative names/mangling patterns that map to this operation.
    /// Stored as null-terminated list for compact representation.
    aliases: []const []const u8,
    /// Where this classification came from.
    evidence: EvidenceSource,
    /// Confidence score [0.0, 1.0] for this classification.
    confidence: f32,

    pub fn init(family: FamilyId, op_kind: ResourceOpKind, canonical_name: []const u8, evidence: EvidenceSource) FamilyOp {
        return .{
            .family = family,
            .op_kind = op_kind,
            .canonical_name = canonical_name,
            .aliases = &.{},
            .evidence = evidence,
            .confidence = if (evidence == .builtin_registry) 1.0 else 0.7,
        };
    }

    pub fn withAliases(self: *FamilyOp, aliases: []const []const u8) void {
        self.aliases = aliases;
    }
};

// ============================================================================
// ResourceFamily — Full description of a resource family
// ============================================================================

/// Complete metadata for a single resource family. The registry stores one
/// of these per FamilyId, describing its kind, lifetime domain, and which
/// other families it considers compatible for release operations.
pub const ResourceFamily = struct {
    /// Unique identifier for this family.
    id: FamilyId,
    /// Human-readable name (e.g., "c_heap", "python_object").
    name: []const u8,
    /// Semantic category of this family.
    kind: FamilyKind,
    /// Lifetime management strategy.
    lifetime_domain: LifetimeDomain,
    /// Families whose release operations are acceptable for this family's allocations.
    /// For example, python_mem may accept python_mem_raw releases (both CPython).
    compatible_release_families: []const FamilyId,
    /// Default confidence for classifications in this family.
    default_confidence: f32,

    /// Check if a given release family is compatible with this allocation family.
    pub fn isCompatibleRelease(self: *const ResourceFamily, release_family: FamilyId) bool {
        if (release_family == self.id) return true;
        for (self.compatible_release_families) |compatible| {
            if (compatible == release_family) return true;
        }
        return false;
    }
};

// ============================================================================
// LookupContext — Additional context for disambiguating lookups
// ============================================================================

/// Context passed to registry lookup calls to help disambiguate between
/// families when the function name alone is ambiguous.
pub const LookupContext = struct {
    /// Known language hint from zone classifier or debug info.
    language_hint: ?LanguageHint = null,
    /// Whether the callee is an extern ("C") function.
    is_extern: bool = false,
    /// Module/name path prefix if available (e.g., "std::", "alloc::").
    namespace_hint: ?[]const u8 = null,

    pub const LanguageHint = enum(u8) {
        c,
        cpp,
        rust,
        python,
        go,
        java,
        csharp,
        zig,
        objective_c,
        swift,
        unknown,
    };
};
