//! Semantic Registry for FFI Boundary Analysis
//!
//! This module provides a knowledge base for FFI boundary function semantics.
//! It is NOT a simple "dangerous function blacklist" - instead, it captures
//! the semantic properties of functions that are relevant when crossing
//! language boundaries.
//!
//! Key insight: The same function has different risk levels depending on context:
//! - `strcpy` in pure C code = medium risk
//! - `strcpy` crossing Rust→C boundary = HIGH risk (length constraint broken, lifetime broken)
//!
//! Layers:
//! - Layer 1: FFI high-risk functions (~15 functions)
//! - Layer 2: Rust ownership patterns (into_raw, from_raw, as_ptr)
//! - Layer 3: Project-specific wrappers (future - config file or annotations)

const std = @import("std");

/// Risk category for FFI boundary analysis.
/// Each category represents a different type of semantic concern.
pub const RiskKind = enum {
    /// Command execution functions (system, exec*, popen)
    command_exec,
    /// Unchecked memory copy (strcpy, strcat, memcpy without bounds)
    unchecked_copy,
    /// Format string vulnerabilities (printf with user input)
    format_string,
    /// Memory allocation (malloc, calloc, realloc)
    allocator,
    /// Memory deallocation (free)
    deallocator,
    /// Rust ownership transfer (Box::into_raw, CString::into_raw)
    rust_ownership,
    /// Borrow escapes to FFI (&str.as_ptr, &slice.as_ptr)
    borrow_escaped,
    /// Memory mapping operations (mmap, munmap, mprotect).
    /// Requires proper pairing: mmap returns ownership, munmap consumes it.
    /// Cross-language mismatch risk when mapping shared memory.
    memory_map,
    /// File I/O operations (fopen, fclose, fread, fwrite, open, close).
    /// Resource ownership tracking: fopen/open transfers ownership,
    /// fclose/close consumes it. Leak risk if not properly paired.
    file_io,
    /// Network I/O operations (socket, connect, bind, listen, accept, send, recv).
    /// Socket ownership: socket/accept transfer ownership, close consumes it.
    /// Security risk: unverified destinations, untrusted input.
    network_io,
    /// Go cgo allocator functions (C.malloc, C.CString, C.free).
    /// Go GC does not manage C memory. Must pair C.malloc with C.free.
    /// Common leak: C.CString returned without caller freeing.
    go_cgo_alloc,
    /// Zig allocator functions (Allocator, gpa, arena).
    /// Zig's allocators require deinit to free memory properly.
    zig_allocator,
    /// C++ allocation functions (new, delete, smart pointers).
    /// new returns ownership, delete consumes it. Smart pointers manage automatically.
    cpp_allocator,
};

/// Severity level for risk assessment.
/// Higher values indicate more critical issues.
pub const Severity = enum(u8) {
    low = 1,
    medium = 2,
    high = 3,
    critical = 4,

    /// Convert severity to string for display
    pub fn toString(self: Severity) []const u8 {
        return switch (self) {
            .low => "LOW",
            .medium => "MEDIUM",
            .high => "HIGH",
            .critical => "CRITICAL",
        };
    }
};

/// Match type for function name patterns.
pub const MatchType = enum {
    /// Exact name match (e.g., "malloc")
    exact,
    /// Prefix match (e.g., "into_raw" matches "std::boxed::Box<T>::into_raw")
    contains,
    /// Suffix match (e.g., "system" matches "\01_system")
    suffix,
};

/// Semantic rule for a function.
/// Captures the behavioral properties relevant to FFI boundary analysis.
pub const FunctionSemantics = struct {
    /// Function name pattern to match
    pattern: []const u8,
    /// How to match the pattern
    match_type: MatchType,
    /// Risk category
    kind: RiskKind,
    /// Severity when crossing FFI boundary
    severity: Severity,
    /// Whether this function consumes ownership of its pointer argument
    consumes_ownership: bool,
    /// Whether this function transfers ownership to the caller
    transfers_ownership: bool,
    /// Whether the result needs null check before use
    requires_null_check: bool,
    /// Whether this function needs taint checking on its arguments
    requires_taint_check: bool,
    /// Human-readable description
    description: []const u8,
};

/// The semantic registry containing all known function semantics.
/// Organized by layers for maintainability.
///
/// Platform Compatibility:
/// - Uses suffix/contains matching to handle platform-specific variants
/// - macOS: system -> \01_system, strcpy -> __strcpy_chk, sprintf -> __sprintf_chk
/// - Linux: Uses standard libc names
pub const SemanticRegistry = struct {
    /// Layer 1: FFI high-risk functions (C standard library)
    /// Uses suffix/contains matching for cross-platform compatibility
    const layer1 = [_]FunctionSemantics{
        // Command execution - CRITICAL
        // macOS: \01_system, Linux: system
        .{
            .pattern = "system",
            .match_type = .suffix,
            .kind = .command_exec,
            .severity = .critical,
            .consumes_ownership = false,
            .transfers_ownership = false,
            .requires_null_check = false,
            .requires_taint_check = true,
            .description = "Execute shell command - command injection risk",
        },
        .{
            .pattern = "popen",
            .match_type = .suffix,
            .kind = .command_exec,
            .severity = .critical,
            .consumes_ownership = false,
            .transfers_ownership = false,
            .requires_null_check = false,
            .requires_taint_check = true,
            .description = "Open pipe to process - command injection risk",
        },
        .{
            .pattern = "execve",
            .match_type = .exact,
            .kind = .command_exec,
            .severity = .critical,
            .consumes_ownership = false,
            .transfers_ownership = false,
            .requires_null_check = false,
            .requires_taint_check = true,
            .description = "Execute program - command injection risk",
        },

        // Unchecked copy - HIGH
        // macOS: __strcpy_chk, __sprintf_chk; Linux: strcpy, sprintf
        .{
            .pattern = "strcpy",
            .match_type = .contains,
            .kind = .unchecked_copy,
            .severity = .high,
            .consumes_ownership = false,
            .transfers_ownership = false,
            .requires_null_check = false,
            .requires_taint_check = true,
            .description = "Unchecked string copy - buffer overflow risk",
        },
        .{
            .pattern = "strcat",
            .match_type = .contains,
            .kind = .unchecked_copy,
            .severity = .high,
            .consumes_ownership = false,
            .transfers_ownership = false,
            .requires_null_check = false,
            .requires_taint_check = true,
            .description = "Unchecked string concatenate - buffer overflow risk",
        },
        .{
            .pattern = "sprintf",
            .match_type = .contains,
            .kind = .unchecked_copy,
            .severity = .high,
            .consumes_ownership = false,
            .transfers_ownership = false,
            .requires_null_check = false,
            .requires_taint_check = true,
            .description = "Unchecked formatted print - buffer overflow risk",
        },
        .{
            .pattern = "vsprintf",
            .match_type = .contains,
            .kind = .unchecked_copy,
            .severity = .high,
            .consumes_ownership = false,
            .transfers_ownership = false,
            .requires_null_check = false,
            .requires_taint_check = true,
            .description = "Unchecked formatted print (va_list) - buffer overflow risk",
        },
        .{
            .pattern = "gets",
            .match_type = .exact,
            .kind = .unchecked_copy,
            .severity = .critical,
            .consumes_ownership = false,
            .transfers_ownership = false,
            .requires_null_check = false,
            .requires_taint_check = true,
            .description = "Read line without bounds - CRITICAL buffer overflow",
        },
        // memcpy - use exact match to avoid matching llvm.memcpy intrinsics
        .{
            .pattern = "memcpy",
            .match_type = .exact,
            .kind = .unchecked_copy,
            .severity = .medium,
            .consumes_ownership = false,
            .transfers_ownership = false,
            .requires_null_check = false,
            .requires_taint_check = true,
            .description = "Memory copy - requires correct size argument",
        },
        // macOS fortified variant
        .{
            .pattern = "__memcpy_chk",
            .match_type = .exact,
            .kind = .unchecked_copy,
            .severity = .medium,
            .consumes_ownership = false,
            .transfers_ownership = false,
            .requires_null_check = false,
            .requires_taint_check = true,
            .description = "Memory copy (fortified) - requires correct size argument",
        },

        // Allocators - MEDIUM (require null check)
        .{
            .pattern = "malloc",
            .match_type = .exact,
            .kind = .allocator,
            .severity = .medium,
            .consumes_ownership = false,
            .transfers_ownership = true,
            .requires_null_check = true,
            .requires_taint_check = false,
            .description = "Allocate memory - returns ownership, check for null",
        },
        .{
            .pattern = "calloc",
            .match_type = .exact,
            .kind = .allocator,
            .severity = .medium,
            .consumes_ownership = false,
            .transfers_ownership = true,
            .requires_null_check = true,
            .requires_taint_check = false,
            .description = "Allocate zeroed memory - returns ownership, check for null",
        },
        .{
            .pattern = "realloc",
            .match_type = .exact,
            .kind = .allocator,
            .severity = .medium,
            .consumes_ownership = true,
            .transfers_ownership = true,
            .requires_null_check = true,
            .requires_taint_check = false,
            .description = "Reallocate memory - consumes old, returns new ownership",
        },

        // Deallocator - HIGH (cross-language free mismatch risk)
        .{
            .pattern = "free",
            .match_type = .exact,
            .kind = .deallocator,
            .severity = .high,
            .consumes_ownership = true,
            .transfers_ownership = false,
            .requires_null_check = false,
            .requires_taint_check = false,
            .description = "Free memory - consumes ownership, cross-language mismatch risk",
        },

        // Memory mapping - HIGH (requires munmap to release)
        .{
            .pattern = "mmap",
            .match_type = .exact,
            .kind = .memory_map,
            .severity = .medium,
            .consumes_ownership = false,
            .transfers_ownership = true,
            .requires_null_check = true,
            .requires_taint_check = false,
            .description = "Map memory - returns ownership, must munmap to release",
        },
        .{
            .pattern = "munmap",
            .match_type = .exact,
            .kind = .memory_map,
            .severity = .high,
            .consumes_ownership = true,
            .transfers_ownership = false,
            .requires_null_check = false,
            .requires_taint_check = false,
            .description = "Unmap memory - consumes ownership, cross-language mismatch risk",
        },
        .{
            .pattern = "mprotect",
            .match_type = .exact,
            .kind = .memory_map,
            .severity = .medium,
            .consumes_ownership = false,
            .transfers_ownership = false,
            .requires_null_check = false,
            .requires_taint_check = false,
            .description = "Change memory protection - can enable execution",
        },

        // File I/O - MEDIUM (resource leak risk)
        .{
            .pattern = "fopen",
            .match_type = .exact,
            .kind = .file_io,
            .severity = .medium,
            .consumes_ownership = false,
            .transfers_ownership = true,
            .requires_null_check = true,
            .requires_taint_check = true,
            .description = "Open file - returns ownership, must fclose to release",
        },
        .{
            .pattern = "fclose",
            .match_type = .exact,
            .kind = .file_io,
            .severity = .medium,
            .consumes_ownership = true,
            .transfers_ownership = false,
            .requires_null_check = false,
            .requires_taint_check = false,
            .description = "Close file - consumes ownership",
        },
        .{
            .pattern = "fread",
            .match_type = .exact,
            .kind = .file_io,
            .severity = .low,
            .consumes_ownership = false,
            .transfers_ownership = false,
            .requires_null_check = false,
            .requires_taint_check = false,
            .description = "Read from file - check return value for errors",
        },
        .{
            .pattern = "fwrite",
            .match_type = .exact,
            .kind = .file_io,
            .severity = .low,
            .consumes_ownership = false,
            .transfers_ownership = false,
            .requires_null_check = false,
            .requires_taint_check = false,
            .description = "Write to file - check return value for errors",
        },
        .{
            .pattern = "fgets",
            .match_type = .exact,
            .kind = .file_io,
            .severity = .low,
            .consumes_ownership = false,
            .transfers_ownership = false,
            .requires_null_check = false,
            .requires_taint_check = false,
            .description = "Read line from file - bounded read, safer than gets",
        },
        .{
            .pattern = "fputs",
            .match_type = .exact,
            .kind = .file_io,
            .severity = .low,
            .consumes_ownership = false,
            .transfers_ownership = false,
            .requires_null_check = false,
            .requires_taint_check = false,
            .description = "Write string to file - check return value",
        },
        .{
            .pattern = "open",
            .match_type = .exact,
            .kind = .file_io,
            .severity = .medium,
            .consumes_ownership = false,
            .transfers_ownership = true,
            .requires_null_check = true,
            .requires_taint_check = true,
            .description = "Open file descriptor - returns ownership, must close",
        },
        .{
            .pattern = "close",
            .match_type = .exact,
            .kind = .file_io,
            .severity = .medium,
            .consumes_ownership = true,
            .transfers_ownership = false,
            .requires_null_check = false,
            .requires_taint_check = false,
            .description = "Close file descriptor - consumes ownership",
        },
        .{
            .pattern = "read",
            .match_type = .exact,
            .kind = .file_io,
            .severity = .low,
            .consumes_ownership = false,
            .transfers_ownership = false,
            .requires_null_check = false,
            .requires_taint_check = false,
            .description = "Read from file descriptor - check return value",
        },
        .{
            .pattern = "write",
            .match_type = .exact,
            .kind = .file_io,
            .severity = .low,
            .consumes_ownership = false,
            .transfers_ownership = false,
            .requires_null_check = false,
            .requires_taint_check = false,
            .description = "Write to file descriptor - check return value",
        },

        // Network I/O - MEDIUM (resource leak and security risk)
        .{
            .pattern = "socket",
            .match_type = .exact,
            .kind = .network_io,
            .severity = .medium,
            .consumes_ownership = false,
            .transfers_ownership = true,
            .requires_null_check = true,
            .requires_taint_check = false,
            .description = "Create socket - returns ownership, must close",
        },
        .{
            .pattern = "connect",
            .match_type = .exact,
            .kind = .network_io,
            .severity = .medium,
            .consumes_ownership = false,
            .transfers_ownership = false,
            .requires_null_check = false,
            .requires_taint_check = true,
            .description = "Connect to server - verify destination address",
        },
        .{
            .pattern = "bind",
            .match_type = .exact,
            .kind = .network_io,
            .severity = .medium,
            .consumes_ownership = false,
            .transfers_ownership = false,
            .requires_null_check = false,
            .requires_taint_check = false,
            .description = "Bind socket to address - check return value",
        },
        .{
            .pattern = "listen",
            .match_type = .exact,
            .kind = .network_io,
            .severity = .low,
            .consumes_ownership = false,
            .transfers_ownership = false,
            .requires_null_check = false,
            .requires_taint_check = false,
            .description = "Listen for connections - check return value",
        },
        .{
            .pattern = "accept",
            .match_type = .exact,
            .kind = .network_io,
            .severity = .medium,
            .consumes_ownership = false,
            .transfers_ownership = true,
            .requires_null_check = true,
            .requires_taint_check = false,
            .description = "Accept connection - returns new socket ownership",
        },
        .{
            .pattern = "recv",
            .match_type = .exact,
            .kind = .network_io,
            .severity = .low,
            .consumes_ownership = false,
            .transfers_ownership = false,
            .requires_null_check = false,
            .requires_taint_check = false,
            .description = "Receive data - check return value, handle partial reads",
        },
        .{
            .pattern = "send",
            .match_type = .exact,
            .kind = .network_io,
            .severity = .low,
            .consumes_ownership = false,
            .transfers_ownership = false,
            .requires_null_check = false,
            .requires_taint_check = false,
            .description = "Send data - check return value, handle partial writes",
        },
        .{
            .pattern = "recvfrom",
            .match_type = .exact,
            .kind = .network_io,
            .severity = .low,
            .consumes_ownership = false,
            .transfers_ownership = false,
            .requires_null_check = false,
            .requires_taint_check = false,
            .description = "Receive data from - check return value",
        },
        .{
            .pattern = "sendto",
            .match_type = .exact,
            .kind = .network_io,
            .severity = .low,
            .consumes_ownership = false,
            .transfers_ownership = false,
            .requires_null_check = false,
            .requires_taint_check = false,
            .description = "Send data to - check return value",
        },

        // Format string - MEDIUM
        .{
            .pattern = "printf",
            .match_type = .contains,
            .kind = .format_string,
            .severity = .medium,
            .consumes_ownership = false,
            .transfers_ownership = false,
            .requires_null_check = false,
            .requires_taint_check = true,
            .description = "Print formatted - format string vulnerability if user-controlled",
        },

        // OpenSSL Crypto API
        .{
            .pattern = "EVP_CIPHER_CTX_new",
            .match_type = .exact,
            .kind = .allocator,
            .severity = .high,
            .consumes_ownership = false,
            .transfers_ownership = true,
            .requires_null_check = true,
            .requires_taint_check = false,
            .description = "OpenSSL cipher context allocation",
        },
        .{
            .pattern = "EVP_CIPHER_CTX_free",
            .match_type = .exact,
            .kind = .deallocator,
            .severity = .high,
            .consumes_ownership = true,
            .transfers_ownership = false,
            .requires_null_check = false,
            .requires_taint_check = false,
            .description = "OpenSSL cipher context deallocation",
        },
        .{
            .pattern = "BIO_new",
            .match_type = .contains,
            .kind = .allocator,
            .severity = .high,
            .consumes_ownership = false,
            .transfers_ownership = true,
            .requires_null_check = true,
            .requires_taint_check = false,
            .description = "OpenSSL BIO allocation",
        },
        .{
            .pattern = "BIO_free",
            .match_type = .exact,
            .kind = .deallocator,
            .severity = .high,
            .consumes_ownership = true,
            .transfers_ownership = false,
            .requires_null_check = false,
            .requires_taint_check = false,
            .description = "OpenSSL BIO deallocation",
        },
        .{
            .pattern = "RSA_new",
            .match_type = .exact,
            .kind = .allocator,
            .severity = .high,
            .consumes_ownership = false,
            .transfers_ownership = true,
            .requires_null_check = true,
            .requires_taint_check = false,
            .description = "OpenSSL RSA key allocation",
        },
        .{
            .pattern = "RSA_free",
            .match_type = .exact,
            .kind = .deallocator,
            .severity = .high,
            .consumes_ownership = true,
            .transfers_ownership = false,
            .requires_null_check = false,
            .requires_taint_check = false,
            .description = "OpenSSL RSA key deallocation",
        },
        .{
            .pattern = "SSL_CTX_new",
            .match_type = .exact,
            .kind = .allocator,
            .severity = .high,
            .consumes_ownership = false,
            .transfers_ownership = true,
            .requires_null_check = true,
            .requires_taint_check = false,
            .description = "OpenSSL SSL context allocation",
        },
        .{
            .pattern = "SSL_CTX_free",
            .match_type = .exact,
            .kind = .deallocator,
            .severity = .high,
            .consumes_ownership = true,
            .transfers_ownership = false,
            .requires_null_check = false,
            .requires_taint_check = false,
            .description = "OpenSSL SSL context deallocation",
        },
        .{
            .pattern = "X509_new",
            .match_type = .exact,
            .kind = .allocator,
            .severity = .medium,
            .consumes_ownership = false,
            .transfers_ownership = true,
            .requires_null_check = true,
            .requires_taint_check = false,
            .description = "OpenSSL X509 certificate allocation",
        },
        .{
            .pattern = "X509_free",
            .match_type = .exact,
            .kind = .deallocator,
            .severity = .medium,
            .consumes_ownership = true,
            .transfers_ownership = false,
            .requires_null_check = false,
            .requires_taint_check = false,
            .description = "OpenSSL X509 certificate deallocation",
        },
        .{
            .pattern = "PEM_read",
            .match_type = .contains,
            .kind = .allocator,
            .severity = .medium,
            .consumes_ownership = false,
            .transfers_ownership = true,
            .requires_null_check = true,
            .requires_taint_check = false,
            .description = "OpenSSL PEM read (allocates object)",
        },

        // SQLite3 API
        .{
            .pattern = "sqlite3_open",
            .match_type = .contains,
            .kind = .allocator,
            .severity = .high,
            .consumes_ownership = false,
            .transfers_ownership = true,
            .requires_null_check = true,
            .requires_taint_check = false,
            .description = "SQLite3 database connection allocation",
        },
        .{
            .pattern = "sqlite3_close",
            .match_type = .exact,
            .kind = .deallocator,
            .severity = .high,
            .consumes_ownership = true,
            .transfers_ownership = false,
            .requires_null_check = false,
            .requires_taint_check = false,
            .description = "SQLite3 database connection deallocation",
        },
        .{
            .pattern = "sqlite3_prepare",
            .match_type = .contains,
            .kind = .allocator,
            .severity = .high,
            .consumes_ownership = false,
            .transfers_ownership = true,
            .requires_null_check = true,
            .requires_taint_check = false,
            .description = "SQLite3 prepared statement allocation",
        },
        .{
            .pattern = "sqlite3_finalize",
            .match_type = .exact,
            .kind = .deallocator,
            .severity = .high,
            .consumes_ownership = true,
            .transfers_ownership = false,
            .requires_null_check = false,
            .requires_taint_check = false,
            .description = "SQLite3 prepared statement deallocation",
        },

        // Zlib Compression API
        .{
            .pattern = "inflateInit",
            .match_type = .contains,
            .kind = .allocator,
            .severity = .medium,
            .consumes_ownership = false,
            .transfers_ownership = true,
            .requires_null_check = true,
            .requires_taint_check = false,
            .description = "Zlib inflate stream initialization (allocates state)",
        },
        .{
            .pattern = "inflateEnd",
            .match_type = .exact,
            .kind = .deallocator,
            .severity = .medium,
            .consumes_ownership = true,
            .transfers_ownership = false,
            .requires_null_check = false,
            .requires_taint_check = false,
            .description = "Zlib inflate stream cleanup (frees state)",
        },
        .{
            .pattern = "deflateInit",
            .match_type = .contains,
            .kind = .allocator,
            .severity = .medium,
            .consumes_ownership = false,
            .transfers_ownership = true,
            .requires_null_check = true,
            .requires_taint_check = false,
            .description = "Zlib deflate stream initialization (allocates state)",
        },
        .{
            .pattern = "deflateEnd",
            .match_type = .exact,
            .kind = .deallocator,
            .severity = .medium,
            .consumes_ownership = true,
            .transfers_ownership = false,
            .requires_null_check = false,
            .requires_taint_check = false,
            .description = "Zlib deflate stream cleanup (frees state)",
        },
        .{
            .pattern = "gzopen",
            .match_type = .exact,
            .kind = .allocator,
            .severity = .medium,
            .consumes_ownership = false,
            .transfers_ownership = true,
            .requires_null_check = true,
            .requires_taint_check = false,
            .description = "Zlib gz file open (allocates handle)",
        },
        .{
            .pattern = "gzclose",
            .match_type = .exact,
            .kind = .deallocator,
            .severity = .medium,
            .consumes_ownership = true,
            .transfers_ownership = false,
            .requires_null_check = false,
            .requires_taint_check = false,
            .description = "Zlib gz file close (frees handle)",
        },
    };

    /// Layer 2: Rust ownership patterns
    const layer2 = [_]FunctionSemantics{
        // Ownership transfer OUT of Rust
        .{
            .pattern = "into_raw",
            .match_type = .contains,
            .kind = .rust_ownership,
            .severity = .high,
            .consumes_ownership = true,
            .transfers_ownership = true,
            .requires_null_check = false,
            .requires_taint_check = false,
            .description = "Rust ownership transfer OUT - caller must free correctly",
        },

        // Ownership transfer INTO Rust
        .{
            .pattern = "from_raw",
            .match_type = .contains,
            .kind = .rust_ownership,
            .severity = .high,
            .consumes_ownership = true,
            .transfers_ownership = true,
            .requires_null_check = false,
            .requires_taint_check = false,
            .description = "Rust ownership transfer IN - Rust takes responsibility",
        },

        // Borrow escape - pointer without ownership transfer
        .{
            .pattern = "as_ptr",
            .match_type = .contains,
            .kind = .borrow_escaped,
            .severity = .medium,
            .consumes_ownership = false,
            .transfers_ownership = false,
            .requires_null_check = false,
            .requires_taint_check = false,
            .description = "Borrow escape - pointer valid only while Rust owns it",
        },
    };

    /// Layer 3: Go cgo allocator patterns
    /// Go's cgo has special memory management rules:
    /// - C.malloc must be freed with C.free (not Go's GC)
    /// - C.CString returns memory that must be freed with C.free
    /// - Go GC does not manage C memory
    const layer3 = [_]FunctionSemantics{
        // Go cgo: C.malloc - must free with C.free
        .{
            .pattern = "C.malloc",
            .match_type = .contains,
            .kind = .go_cgo_alloc,
            .severity = .medium,
            .consumes_ownership = false,
            .transfers_ownership = true,
            .requires_null_check = true,
            .requires_taint_check = false,
            .description = "Go cgo malloc - must free with C.free, not Go GC",
        },
        // Go cgo: C.CString - allocates C string, caller must free
        .{
            .pattern = "C.CString",
            .match_type = .contains,
            .kind = .go_cgo_alloc,
            .severity = .medium,
            .consumes_ownership = false,
            .transfers_ownership = true,
            .requires_null_check = true,
            .requires_taint_check = false,
            .description = "Go cgo CString - caller must free with C.free",
        },
        // Go cgo: C.CBytes - allocates C bytes, caller must free
        .{
            .pattern = "C.CBytes",
            .match_type = .contains,
            .kind = .go_cgo_alloc,
            .severity = .medium,
            .consumes_ownership = false,
            .transfers_ownership = true,
            .requires_null_check = true,
            .requires_taint_check = false,
            .description = "Go cgo CBytes - caller must free with C.free",
        },
        // Go cgo: C.free - frees C memory
        .{
            .pattern = "C.free",
            .match_type = .contains,
            .kind = .go_cgo_alloc,
            .severity = .high,
            .consumes_ownership = true,
            .transfers_ownership = false,
            .requires_null_check = false,
            .requires_taint_check = false,
            .description = "Go cgo free - frees C memory, not managed by Go GC",
        },
    };

    /// Layer 4: Swift FFI patterns
    /// Swift uses reference counting and has special FFI considerations:
    /// - UnsafeMutablePointer for C interop
    /// - withUnsafeBytes/withUnsafeMutableBytes for temporary access
    /// - Swift mangling: $s prefix
    const layer4 = [_]FunctionSemantics{
        // Swift: withUnsafeBytes - temporary pointer access
        .{
            .pattern = "withUnsafeBytes",
            .match_type = .contains,
            .kind = .borrow_escaped,
            .severity = .medium,
            .consumes_ownership = false,
            .transfers_ownership = false,
            .requires_null_check = false,
            .requires_taint_check = false,
            .description = "Swift unsafe bytes access - pointer valid only in closure",
        },
        // Swift: withUnsafeMutableBytes - temporary mutable pointer access
        .{
            .pattern = "withUnsafeMutableBytes",
            .match_type = .contains,
            .kind = .borrow_escaped,
            .severity = .medium,
            .consumes_ownership = false,
            .transfers_ownership = false,
            .requires_null_check = false,
            .requires_taint_check = false,
            .description = "Swift unsafe mutable bytes - pointer valid only in closure",
        },
        // Swift: UnsafeMutablePointer.allocate - must deallocate
        .{
            .pattern = "UnsafeMutablePointer",
            .match_type = .contains,
            .kind = .allocator,
            .severity = .medium,
            .consumes_ownership = false,
            .transfers_ownership = true,
            .requires_null_check = true,
            .requires_taint_check = false,
            .description = "Swift unsafe pointer allocation - must deallocate",
        },
        // Swift: bridged cast
        .{
            .pattern = "unsafeBitCast",
            .match_type = .contains,
            .kind = .borrow_escaped,
            .severity = .medium,
            .consumes_ownership = false,
            .transfers_ownership = false,
            .requires_null_check = false,
            .requires_taint_check = false,
            .description = "Swift unsafe bit cast - reinterpretation without ownership change",
        },
        // Swift: raw pointer initialization
        .{
            .pattern = "UnsafeRawPointer",
            .match_type = .contains,
            .kind = .allocator,
            .severity = .medium,
            .consumes_ownership = false,
            .transfers_ownership = true,
            .requires_null_check = false,
            .requires_taint_check = false,
            .description = "Swift raw pointer initialization - caller owns memory",
        },
        // Swift: withExtendedLifetime
        .{
            .pattern = "withExtendedLifetime",
            .match_type = .contains,
            .kind = .borrow_escaped,
            .severity = .low,
            .consumes_ownership = false,
            .transfers_ownership = false,
            .requires_null_check = false,
            .requires_taint_check = false,
            .description = "Swift extended lifetime - temporary lifetime extension",
        },
        // Swift: Unmanaged
        .{
            .pattern = "Unmanaged",
            .match_type = .contains,
            .kind = .rust_ownership,
            .severity = .medium,
            .consumes_ownership = false,
            .transfers_ownership = true,
            .requires_null_check = false,
            .requires_taint_check = false,
            .description = "Swift Unmanaged - manual reference counting, transfer ownership",
        },
        // Swift: autoreleasepool
        .{
            .pattern = "autoreleasepool",
            .match_type = .contains,
            .kind = .borrow_escaped,
            .severity = .low,
            .consumes_ownership = false,
            .transfers_ownership = false,
            .requires_null_check = false,
            .requires_taint_check = false,
            .description = "Swift autorelease pool - temporary memory management",
        },
    };

    /// Layer 5: Zig Standard Library patterns
    /// Zig uses explicit allocators and optional types:
    /// - gpa (GeneralPurposeAllocator) requires deinit
    /// - ArenaAllocator requires deinit
    /// - Optional types require null check
    const layer5 = [_]FunctionSemantics{
        // Zig: GeneralPurposeAllocator
        .{
            .pattern = "GeneralPurposeAllocator",
            .match_type = .contains,
            .kind = .zig_allocator,
            .severity = .medium,
            .consumes_ownership = false,
            .transfers_ownership = true,
            .requires_null_check = false,
            .requires_taint_check = false,
            .description = "Zig GPA - requires deinit to release memory",
        },
        // Zig: ArenaAllocator
        .{
            .pattern = "ArenaAllocator",
            .match_type = .contains,
            .kind = .zig_allocator,
            .severity = .medium,
            .consumes_ownership = false,
            .transfers_ownership = true,
            .requires_null_check = false,
            .requires_taint_check = false,
            .description = "Zig arena allocator - requires deinit to release all memory",
        },
        // Zig: FixedBufferAllocator
        .{
            .pattern = "FixedBufferAllocator",
            .match_type = .contains,
            .kind = .zig_allocator,
            .severity = .low,
            .consumes_ownership = false,
            .transfers_ownership = true,
            .requires_null_check = false,
            .requires_taint_check = false,
            .description = "Zig fixed buffer allocator - stack-allocated memory",
        },
        // Zig: pageAllocator
        .{
            .pattern = "pageAllocator",
            .match_type = .contains,
            .kind = .zig_allocator,
            .severity = .medium,
            .consumes_ownership = false,
            .transfers_ownership = true,
            .requires_null_check = false,
            .requires_taint_check = false,
            .description = "Zig page allocator - system memory allocation",
        },
        // Zig: allocator.alloc
        .{
            .pattern = "alloc",
            .match_type = .contains,
            .kind = .zig_allocator,
            .severity = .medium,
            .consumes_ownership = false,
            .transfers_ownership = true,
            .requires_null_check = true,
            .requires_taint_check = false,
            .description = "Zig allocator alloc - returns optional pointer, requires null check",
        },
        // Zig: allocator.create
        .{
            .pattern = "create(",
            .match_type = .contains,
            .kind = .zig_allocator,
            .severity = .medium,
            .consumes_ownership = false,
            .transfers_ownership = true,
            .requires_null_check = true,
            .requires_taint_check = false,
            .description = "Zig allocator create - single item allocation",
        },
        // Zig: allocator.destroy
        .{
            .pattern = "destroy(",
            .match_type = .contains,
            .kind = .zig_allocator,
            .severity = .high,
            .consumes_ownership = true,
            .transfers_ownership = false,
            .requires_null_check = false,
            .requires_taint_check = false,
            .description = "Zig allocator destroy - frees memory, ownership consumed",
        },
        // Zig: allocator.free
        .{
            .pattern = "free(",
            .match_type = .contains,
            .kind = .zig_allocator,
            .severity = .high,
            .consumes_ownership = true,
            .transfers_ownership = false,
            .requires_null_check = false,
            .requires_taint_check = false,
            .description = "Zig allocator free - frees memory, ownership consumed",
        },
        // Zig: ArrayList.init
        .{
            .pattern = "ArrayList",
            .match_type = .contains,
            .kind = .zig_allocator,
            .severity = .medium,
            .consumes_ownership = false,
            .transfers_ownership = true,
            .requires_null_check = false,
            .requires_taint_check = false,
            .description = "Zig ArrayList - requires deinit to free internal memory",
        },
        // Zig: HashMap
        .{
            .pattern = "HashMap",
            .match_type = .contains,
            .kind = .zig_allocator,
            .severity = .medium,
            .consumes_ownership = false,
            .transfers_ownership = true,
            .requires_null_check = false,
            .requires_taint_check = false,
            .description = "Zig HashMap - requires deinit to free internal memory",
        },
        // Zig: AutoHashMap
        .{
            .pattern = "AutoHashMap",
            .match_type = .contains,
            .kind = .zig_allocator,
            .severity = .medium,
            .consumes_ownership = false,
            .transfers_ownership = true,
            .requires_null_check = false,
            .requires_taint_check = false,
            .description = "Zig AutoHashMap - requires deinit to free internal memory",
        },
        // Zig: StringHashMap
        .{
            .pattern = "StringHashMap",
            .match_type = .contains,
            .kind = .zig_allocator,
            .severity = .medium,
            .consumes_ownership = false,
            .transfers_ownership = true,
            .requires_null_check = false,
            .requires_taint_check = false,
            .description = "Zig StringHashMap - requires deinit to free internal memory",
        },
        // Zig: std.mem.alloctor
        .{
            .pattern = "std.mem.allocator",
            .match_type = .contains,
            .kind = .zig_allocator,
            .severity = .medium,
            .consumes_ownership = false,
            .transfers_ownership = false,
            .requires_null_check = false,
            .requires_taint_check = false,
            .description = "Zig std.mem - allocation functions require pairing with free",
        },
        // Zig: std.heap
        .{
            .pattern = "std.heap",
            .match_type = .contains,
            .kind = .zig_allocator,
            .severity = .medium,
            .consumes_ownership = false,
            .transfers_ownership = false,
            .requires_null_check = false,
            .requires_taint_check = false,
            .description = "Zig std.heap - heap allocation primitives",
        },
        // Zig: Optional (.?) - requires null check
        .{
            .pattern = ".?",
            .match_type = .suffix,
            .kind = .borrow_escaped,
            .severity = .low,
            .consumes_ownership = false,
            .transfers_ownership = false,
            .requires_null_check = true,
            .requires_taint_check = false,
            .description = "Zig optional unwrap - requires null check",
        },
        // Zig: error union (.!|) - requires error check
        .{
            .pattern = ".!|",
            .match_type = .suffix,
            .kind = .borrow_escaped,
            .severity = .medium,
            .consumes_ownership = false,
            .transfers_ownership = false,
            .requires_null_check = false,
            .requires_taint_check = false,
            .description = "Zig error union - requires error check",
        },
        // Zig: @ptrCast
        .{
            .pattern = "@ptrCast",
            .match_type = .contains,
            .kind = .borrow_escaped,
            .severity = .medium,
            .consumes_ownership = false,
            .transfers_ownership = false,
            .requires_null_check = false,
            .requires_taint_check = false,
            .description = "Zig ptr cast - pointer type conversion",
        },
        // Zig: @intToPtr
        .{
            .pattern = "@intToPtr",
            .match_type = .contains,
            .kind = .borrow_escaped,
            .severity = .high,
            .consumes_ownership = false,
            .transfers_ownership = false,
            .requires_null_check = false,
            .requires_taint_check = false,
            .description = "Zig intToPtr - integer to pointer conversion",
        },
        // Zig: @ptrToInt
        .{
            .pattern = "@ptrToInt",
            .match_type = .contains,
            .kind = .borrow_escaped,
            .severity = .low,
            .consumes_ownership = false,
            .transfers_ownership = false,
            .requires_null_check = false,
            .requires_taint_check = false,
            .description = "Zig ptrToInt - pointer to integer conversion",
        },
        // Zig: SliceAllocator
        .{
            .pattern = "SliceAllocator",
            .match_type = .contains,
            .kind = .zig_allocator,
            .severity = .medium,
            .consumes_ownership = false,
            .transfers_ownership = true,
            .requires_null_check = false,
            .requires_taint_check = false,
            .description = "Zig SliceAllocator - allocator for slice operations",
        },
        // Zig: logging allocator
        .{
            .pattern = "LoggingAllocator",
            .match_type = .contains,
            .kind = .zig_allocator,
            .severity = .low,
            .consumes_ownership = false,
            .transfers_ownership = true,
            .requires_null_check = false,
            .requires_taint_check = false,
            .description = "Zig LoggingAllocator - wraps another allocator for debugging",
        },
        // Zig: sentinel terminated
        .{
            .pattern = "sentinel",
            .match_type = .contains,
            .kind = .borrow_escaped,
            .severity = .low,
            .consumes_ownership = false,
            .transfers_ownership = false,
            .requires_null_check = false,
            .requires_taint_check = false,
            .description = "Zig sentinel terminated - memory with sentinel value",
        },
        // Zig: threadlocal allocator
        .{
            .pattern = "threadlocal",
            .match_type = .contains,
            .kind = .zig_allocator,
            .severity = .low,
            .consumes_ownership = false,
            .transfers_ownership = false,
            .requires_null_check = false,
            .requires_taint_check = false,
            .description = "Zig threadlocal - thread-local memory allocation",
        },
        // Zig: c_allocator (C interoperability)
        .{
            .pattern = "c_allocator",
            .match_type = .contains,
            .kind = .zig_allocator,
            .severity = .medium,
            .consumes_ownership = false,
            .transfers_ownership = true,
            .requires_null_check = false,
            .requires_taint_check = false,
            .description = "Zig c_allocator - libc malloc wrapper for C interoperability",
        },
        // Zig: rawSliceAlloc
        .{
            .pattern = "rawSliceAlloc",
            .match_type = .contains,
            .kind = .zig_allocator,
            .severity = .medium,
            .consumes_ownership = false,
            .transfers_ownership = true,
            .requires_null_check = false,
            .requires_taint_check = false,
            .description = "Zig rawSliceAlloc - low-level slice allocation",
        },
    };

    /// Layer 6: C++ Standard Library patterns
    /// C++ has complex ownership semantics:
    /// - new/delete for raw pointers
    /// - std::unique_ptr for exclusive ownership
    /// - std::shared_ptr for shared ownership
    /// - std::weak_ptr for weak references
    const layer6 = [_]FunctionSemantics{
        // C++: new
        .{
            .pattern = "operator new",
            .match_type = .contains,
            .kind = .cpp_allocator,
            .severity = .high,
            .consumes_ownership = false,
            .transfers_ownership = true,
            .requires_null_check = false,
            .requires_taint_check = false,
            .description = "C++ new - allocates memory, caller must delete",
        },
        // C++: new[]
        .{
            .pattern = "operator new[]",
            .match_type = .contains,
            .kind = .cpp_allocator,
            .severity = .high,
            .consumes_ownership = false,
            .transfers_ownership = true,
            .requires_null_check = false,
            .requires_taint_check = false,
            .description = "C++ new[] - array allocation, caller must delete[]",
        },
        // C++: delete
        .{
            .pattern = "operator delete",
            .match_type = .contains,
            .kind = .cpp_allocator,
            .severity = .high,
            .consumes_ownership = true,
            .transfers_ownership = false,
            .requires_null_check = false,
            .requires_taint_check = false,
            .description = "C++ delete - frees memory, consumes ownership",
        },
        // C++: delete[]
        .{
            .pattern = "operator delete[]",
            .match_type = .contains,
            .kind = .cpp_allocator,
            .severity = .high,
            .consumes_ownership = true,
            .transfers_ownership = false,
            .requires_null_check = false,
            .requires_taint_check = false,
            .description = "C++ delete[] - frees array memory, consumes ownership",
        },
        // C++: std::make_unique
        .{
            .pattern = "make_unique",
            .match_type = .contains,
            .kind = .cpp_allocator,
            .severity = .medium,
            .consumes_ownership = false,
            .transfers_ownership = true,
            .requires_null_check = false,
            .requires_taint_check = false,
            .description = "C++ std::make_unique - creates unique_ptr, automatic ownership",
        },
        // C++: std::make_shared
        .{
            .pattern = "make_shared",
            .match_type = .contains,
            .kind = .cpp_allocator,
            .severity = .medium,
            .consumes_ownership = false,
            .transfers_ownership = true,
            .requires_null_check = false,
            .requires_taint_check = false,
            .description = "C++ std::make_shared - creates shared_ptr, automatic ownership",
        },
        // C++: std::unique_ptr
        .{
            .pattern = "unique_ptr",
            .match_type = .contains,
            .kind = .cpp_allocator,
            .severity = .medium,
            .consumes_ownership = false,
            .transfers_ownership = true,
            .requires_null_check = false,
            .requires_taint_check = false,
            .description = "C++ std::unique_ptr - exclusive ownership, auto-release",
        },
        // C++: std::shared_ptr
        .{
            .pattern = "shared_ptr",
            .match_type = .contains,
            .kind = .cpp_allocator,
            .severity = .medium,
            .consumes_ownership = false,
            .transfers_ownership = true,
            .requires_null_check = false,
            .requires_taint_check = false,
            .description = "C++ std::shared_ptr - shared ownership, ref-counted",
        },
        // C++: std::weak_ptr
        .{
            .pattern = "weak_ptr",
            .match_type = .contains,
            .kind = .borrow_escaped,
            .severity = .medium,
            .consumes_ownership = false,
            .transfers_ownership = false,
            .requires_null_check = true,
            .requires_taint_check = false,
            .description = "C++ std::weak_ptr - non-owning reference, lock for access",
        },
        // C++: std::move
        .{
            .pattern = "std::move",
            .match_type = .contains,
            .kind = .rust_ownership,
            .severity = .medium,
            .consumes_ownership = false,
            .transfers_ownership = true,
            .requires_null_check = false,
            .requires_taint_check = false,
            .description = "C++ std::move - transfers ownership (move semantics)",
        },
        // C++: std::forward
        .{
            .pattern = "std::forward",
            .match_type = .contains,
            .kind = .borrow_escaped,
            .severity = .low,
            .consumes_ownership = false,
            .transfers_ownership = false,
            .requires_null_check = false,
            .requires_taint_check = false,
            .description = "C++ std::forward - perfect forwarding, preserves value category",
        },
        // C++: std::malloc
        .{
            .pattern = "std::malloc",
            .match_type = .contains,
            .kind = .allocator,
            .severity = .medium,
            .consumes_ownership = false,
            .transfers_ownership = true,
            .requires_null_check = true,
            .requires_taint_check = false,
            .description = "C++ std::malloc - C allocation, requires free",
        },
        // C++: std::free
        .{
            .pattern = "std::free",
            .match_type = .contains,
            .kind = .deallocator,
            .severity = .high,
            .consumes_ownership = true,
            .transfers_ownership = false,
            .requires_null_check = false,
            .requires_taint_check = false,
            .description = "C++ std::free - C deallocation, consumes ownership",
        },
        // C++: std::vector
        .{
            .pattern = "std::vector",
            .match_type = .contains,
            .kind = .cpp_allocator,
            .severity = .medium,
            .consumes_ownership = false,
            .transfers_ownership = true,
            .requires_null_check = false,
            .requires_taint_check = false,
            .description = "C++ std::vector - dynamic array, automatic memory management",
        },
        // C++: std::string
        .{
            .pattern = "std::string",
            .match_type = .contains,
            .kind = .cpp_allocator,
            .severity = .medium,
            .consumes_ownership = false,
            .transfers_ownership = true,
            .requires_null_check = false,
            .requires_taint_check = false,
            .description = "C++ std::string - string class, automatic memory management",
        },
        // C++: std::array
        .{
            .pattern = "std::array",
            .match_type = .contains,
            .kind = .borrow_escaped,
            .severity = .low,
            .consumes_ownership = false,
            .transfers_ownership = false,
            .requires_null_check = false,
            .requires_taint_check = false,
            .description = "C++ std::array - fixed-size array, stack allocated",
        },
        // C++: std::optional
        .{
            .pattern = "std::optional",
            .match_type = .contains,
            .kind = .borrow_escaped,
            .severity = .low,
            .consumes_ownership = false,
            .transfers_ownership = false,
            .requires_null_check = true,
            .requires_taint_check = false,
            .description = "C++ std::optional - may or may not contain a value",
        },
        // C++: std::unique_lock
        .{
            .pattern = "unique_lock",
            .match_type = .contains,
            .kind = .borrow_escaped,
            .severity = .medium,
            .consumes_ownership = false,
            .transfers_ownership = false,
            .requires_null_check = false,
            .requires_taint_check = false,
            .description = "C++ std::unique_lock - RAII lock, auto-release on destruction",
        },
        // C++: std::lock_guard
        .{
            .pattern = "lock_guard",
            .match_type = .contains,
            .kind = .borrow_escaped,
            .severity = .medium,
            .consumes_ownership = false,
            .transfers_ownership = false,
            .requires_null_check = false,
            .requires_taint_check = false,
            .description = "C++ std::lock_guard - RAII lock, auto-release on destruction",
        },
        // C++: std::shared_lock
        .{
            .pattern = "shared_lock",
            .match_type = .contains,
            .kind = .borrow_escaped,
            .severity = .medium,
            .consumes_ownership = false,
            .transfers_ownership = false,
            .requires_null_check = false,
            .requires_taint_check = false,
            .description = "C++ std::shared_lock - RAII reader lock",
        },
        // C++: std::promise
        .{
            .pattern = "std::promise",
            .match_type = .contains,
            .kind = .borrow_escaped,
            .severity = .medium,
            .consumes_ownership = false,
            .transfers_ownership = true,
            .requires_null_check = false,
            .requires_taint_check = false,
            .description = "C++ std::promise - asynchronous value holder",
        },
        // C++: std::future
        .{
            .pattern = "std::future",
            .match_type = .contains,
            .kind = .borrow_escaped,
            .severity = .medium,
            .consumes_ownership = false,
            .transfers_ownership = false,
            .requires_null_check = false,
            .requires_taint_check = false,
            .description = "C++ std::future - asynchronous result retrieval",
        },
        // C++: std::packaged_task
        .{
            .pattern = "packaged_task",
            .match_type = .contains,
            .kind = .borrow_escaped,
            .severity = .medium,
            .consumes_ownership = false,
            .transfers_ownership = true,
            .requires_null_check = false,
            .requires_taint_check = false,
            .description = "C++ std::packaged_task - asynchronous callable wrapper",
        },
        // C++: std::thread
        .{
            .pattern = "std::thread",
            .match_type = .contains,
            .kind = .cpp_allocator,
            .severity = .medium,
            .consumes_ownership = false,
            .transfers_ownership = true,
            .requires_null_check = false,
            .requires_taint_check = false,
            .description = "C++ std::thread - thread of execution, join/detach required",
        },
        // C++: std::async
        .{
            .pattern = "std::async",
            .match_type = .contains,
            .kind = .cpp_allocator,
            .severity = .medium,
            .consumes_ownership = false,
            .transfers_ownership = true,
            .requires_null_check = false,
            .requires_taint_check = false,
            .description = "C++ std::async - asynchronous function execution",
        },
        // C++: std::exchange
        .{
            .pattern = "std::exchange",
            .match_type = .contains,
            .kind = .rust_ownership,
            .severity = .medium,
            .consumes_ownership = false,
            .transfers_ownership = true,
            .requires_null_check = false,
            .requires_taint_check = false,
            .description = "C++ std::exchange - assigns new value, returns old",
        },
        // C++: std::owner_less
        .{
            .pattern = "owner_less",
            .match_type = .contains,
            .kind = .borrow_escaped,
            .severity = .low,
            .consumes_ownership = false,
            .transfers_ownership = false,
            .requires_null_check = false,
            .requires_taint_check = false,
            .description = "C++ owner_less - comparator for smart pointer ownership",
        },
        // C++: enable_shared_from_this
        .{
            .pattern = "enable_shared_from_this",
            .match_type = .contains,
            .kind = .borrow_escaped,
            .severity = .medium,
            .consumes_ownership = false,
            .transfers_ownership = false,
            .requires_null_check = false,
            .requires_taint_check = false,
            .description = "C++ enable_shared_from_this - safe self-reference in shared_ptr",
        },
        // C++: static_cast
        .{
            .pattern = "static_cast",
            .match_type = .contains,
            .kind = .borrow_escaped,
            .severity = .low,
            .consumes_ownership = false,
            .transfers_ownership = false,
            .requires_null_check = false,
            .requires_taint_check = false,
            .description = "C++ static_cast - compile-time checked cast",
        },
        // C++: reinterpret_cast
        .{
            .pattern = "reinterpret_cast",
            .match_type = .contains,
            .kind = .borrow_escaped,
            .severity = .medium,
            .consumes_ownership = false,
            .transfers_ownership = false,
            .requires_null_check = false,
            .requires_taint_check = false,
            .description = "C++ reinterpret_cast - unsafe type conversion",
        },
        // C++: dynamic_cast
        .{
            .pattern = "dynamic_cast",
            .match_type = .contains,
            .kind = .borrow_escaped,
            .severity = .medium,
            .consumes_ownership = false,
            .transfers_ownership = false,
            .requires_null_check = true,
            .requires_taint_check = false,
            .description = "C++ dynamic_cast - runtime checked cast, returns null on failure",
        },
        // C++: std::bad_cast
        .{
            .pattern = "bad_cast",
            .match_type = .contains,
            .kind = .borrow_escaped,
            .severity = .medium,
            .consumes_ownership = false,
            .transfers_ownership = false,
            .requires_null_check = false,
            .requires_taint_check = false,
            .description = "C++ bad_cast - exception from failed dynamic_cast",
        },
        // C++: std::nothrow
        .{
            .pattern = "std::nothrow",
            .match_type = .contains,
            .kind = .borrow_escaped,
            .severity = .low,
            .consumes_ownership = false,
            .transfers_ownership = false,
            .requires_null_check = true,
            .requires_taint_check = false,
            .description = "C++ nothrow - non-throwing allocation, returns null on failure",
        },
        // C++: std::align_val_t
        .{
            .pattern = "align_val_t",
            .match_type = .contains,
            .kind = .borrow_escaped,
            .severity = .low,
            .consumes_ownership = false,
            .transfers_ownership = false,
            .requires_null_check = false,
            .requires_taint_check = false,
            .description = "C++ align_val_t - aligned allocation tag type",
        },
        // C++: std::launder
        .{
            .pattern = "std::launder",
            .match_type = .contains,
            .kind = .borrow_escaped,
            .severity = .medium,
            .consumes_ownership = false,
            .transfers_ownership = false,
            .requires_null_check = false,
            .requires_taint_check = false,
            .description = "C++ std::launder - retreive pointer to object stored in memory",
        },
        // C++: std::hardware_destructive_interference_size
        .{
            .pattern = "hardware_destructive_interference_size",
            .match_type = .contains,
            .kind = .borrow_escaped,
            .severity = .low,
            .consumes_ownership = false,
            .transfers_ownership = false,
            .requires_null_check = false,
            .requires_taint_check = false,
            .description = "C++ cache line size hint for false sharing avoidance",
        },
        // C++: std::in_place
        .{
            .pattern = "std::in_place",
            .match_type = .contains,
            .kind = .borrow_escaped,
            .severity = .low,
            .consumes_ownership = false,
            .transfers_ownership = false,
            .requires_null_check = false,
            .requires_taint_check = false,
            .description = "C++ in_place - construct in-place tag",
        },
        // C++: std::allocate_shared
        .{
            .pattern = "allocate_shared",
            .match_type = .contains,
            .kind = .cpp_allocator,
            .severity = .medium,
            .consumes_ownership = false,
            .transfers_ownership = true,
            .requires_null_check = false,
            .requires_taint_check = false,
            .description = "C++ allocate_shared - creates shared_ptr with custom allocator",
        },
        // C++: std::declare_reachable
        .{
            .pattern = "declare_reachable",
            .match_type = .contains,
            .kind = .borrow_escaped,
            .severity = .low,
            .consumes_ownership = false,
            .transfers_ownership = false,
            .requires_null_check = false,
            .requires_taint_check = false,
            .description = "C++ declare_reachable - marks memory as reachable to GC",
        },
        // C++: std::undeclare_reachable
        .{
            .pattern = "undeclare_reachable",
            .match_type = .contains,
            .kind = .borrow_escaped,
            .severity = .low,
            .consumes_ownership = false,
            .transfers_ownership = false,
            .requires_null_check = false,
            .requires_taint_check = false,
            .description = "C++ undeclare_reachable - removes reachable marking",
        },
        // C++: std::ref, std::cref
        .{
            .pattern = "std::ref",
            .match_type = .contains,
            .kind = .borrow_escaped,
            .severity = .low,
            .consumes_ownership = false,
            .transfers_ownership = false,
            .requires_null_check = false,
            .requires_taint_check = false,
            .description = "C++ std::ref/std::cref - reference wrapper objects",
        },
        // C++: std::bind
        .{
            .pattern = "std::bind",
            .match_type = .contains,
            .kind = .borrow_escaped,
            .severity = .low,
            .consumes_ownership = false,
            .transfers_ownership = false,
            .requires_null_check = false,
            .requires_taint_check = false,
            .description = "C++ std::bind - function adapter, binds arguments",
        },
        // C++: std::function
        .{
            .pattern = "std::function",
            .match_type = .contains,
            .kind = .borrow_escaped,
            .severity = .low,
            .consumes_ownership = false,
            .transfers_ownership = false,
            .requires_null_check = false,
            .requires_taint_check = false,
            .description = "C++ std::function - type-erased callable wrapper",
        },
        // C++: std::mem_fn
        .{
            .pattern = "std::mem_fn",
            .match_type = .contains,
            .kind = .borrow_escaped,
            .severity = .low,
            .consumes_ownership = false,
            .transfers_ownership = false,
            .requires_null_check = false,
            .requires_taint_check = false,
            .description = "C++ mem_fn - create member function callable",
        },
        // C++: std::mem_card
        .{
            .pattern = "mem_card",
            .match_type = .contains,
            .kind = .borrow_escaped,
            .severity = .low,
            .consumes_ownership = false,
            .transfers_ownership = false,
            .requires_null_check = false,
            .requires_taint_check = false,
            .description = "C++ mem_card - memory cardinality properties",
        },
        // C++: std::hash
        .{
            .pattern = "std::hash",
            .match_type = .contains,
            .kind = .borrow_escaped,
            .severity = .low,
            .consumes_ownership = false,
            .transfers_ownership = false,
            .requires_null_check = false,
            .requires_taint_check = false,
            .description = "C++ std::hash - hash function object",
        },
        // C++: std::equal_to
        .{
            .pattern = "std::equal_to",
            .match_type = .contains,
            .kind = .borrow_escaped,
            .severity = .low,
            .consumes_ownership = false,
            .transfers_ownership = false,
            .requires_null_check = false,
            .requires_taint_check = false,
            .description = "C++ std::equal_to - equality comparison function object",
        },
        // C++: std::less
        .{
            .pattern = "std::less",
            .match_type = .contains,
            .kind = .borrow_escaped,
            .severity = .low,
            .consumes_ownership = false,
            .transfers_ownership = false,
            .requires_null_check = false,
            .requires_taint_check = false,
            .description = "C++ std::less - less-than comparison function object",
        },
        // C++: std::chrono
        .{
            .pattern = "std::chrono",
            .match_type = .contains,
            .kind = .borrow_escaped,
            .severity = .low,
            .consumes_ownership = false,
            .transfers_ownership = false,
            .requires_null_check = false,
            .requires_taint_check = false,
            .description = "C++ std::chrono - time utilities",
        },
        // C++: std::addressof
        .{
            .pattern = "std::addressof",
            .match_type = .contains,
            .kind = .borrow_escaped,
            .severity = .low,
            .consumes_ownership = false,
            .transfers_ownership = false,
            .requires_null_check = false,
            .requires_taint_check = false,
            .description = "C++ std::addressof - get actual address of object",
        },
        // C++: std::exchange
        .{
            .pattern = "std::get_temporary_buffer",
            .match_type = .contains,
            .kind = .allocator,
            .severity = .medium,
            .consumes_ownership = false,
            .transfers_ownership = true,
            .requires_null_check = true,
            .requires_taint_check = false,
            .description = "C++ get_temporary_buffer - temporary buffer allocation",
        },
        // C++: std::return_temporary_buffer
        .{
            .pattern = "return_temporary_buffer",
            .match_type = .contains,
            .kind = .deallocator,
            .severity = .high,
            .consumes_ownership = true,
            .transfers_ownership = false,
            .requires_null_check = false,
            .requires_taint_check = false,
            .description = "C++ return_temporary_buffer - return temporary buffer memory",
        },
        // C++: std::tuple
        .{
            .pattern = "std::tuple",
            .match_type = .contains,
            .kind = .borrow_escaped,
            .severity = .low,
            .consumes_ownership = false,
            .transfers_ownership = false,
            .requires_null_check = false,
            .requires_taint_check = false,
            .description = "C++ std::tuple - fixed-size heterogeneous container",
        },
        // C++: std::pair
        .{
            .pattern = "std::pair",
            .match_type = .contains,
            .kind = .borrow_escaped,
            .severity = .low,
            .consumes_ownership = false,
            .transfers_ownership = false,
            .requires_null_check = false,
            .requires_taint_check = false,
            .description = "C++ std::pair - two-element container",
        },
    };

    /// Lookup function semantics by name.
    /// Searches Layer 1 first, then Layer 2, 3, 4, 5, 6.
    /// Returns null if function is not in the registry.
    pub fn lookup(func_name: []const u8) ?FunctionSemantics {
        // Search Layer 1 (FFI high-risk functions)
        for (layer1) |sem| {
            if (matchesPattern(func_name, sem.pattern, sem.match_type)) {
                return sem;
            }
        }

        // Search Layer 2 (Rust ownership patterns)
        for (layer2) |sem| {
            if (matchesPattern(func_name, sem.pattern, sem.match_type)) {
                return sem;
            }
        }

        // Search Layer 3 (Go cgo allocator patterns)
        for (layer3) |sem| {
            if (matchesPattern(func_name, sem.pattern, sem.match_type)) {
                return sem;
            }
        }

        // Search Layer 4 (Swift FFI patterns)
        for (layer4) |sem| {
            if (matchesPattern(func_name, sem.pattern, sem.match_type)) {
                return sem;
            }
        }

        // Search Layer 5 (Zig patterns)
        for (layer5) |sem| {
            if (matchesPattern(func_name, sem.pattern, sem.match_type)) {
                return sem;
            }
        }

        // Search Layer 6 (C++ patterns)
        for (layer6) |sem| {
            if (matchesPattern(func_name, sem.pattern, sem.match_type)) {
                return sem;
            }
        }

        return null;
    }

    /// Check if a function name matches a pattern.
    fn matchesPattern(func_name: []const u8, pattern: []const u8, match_type: MatchType) bool {
        return switch (match_type) {
            .exact => std.mem.eql(u8, func_name, pattern),
            .contains => std.mem.indexOf(u8, func_name, pattern) != null,
            .suffix => std.mem.endsWith(u8, func_name, pattern),
        };
    }

    /// Check if a function is known to the registry.
    pub fn isKnown(func_name: []const u8) bool {
        return lookup(func_name) != null;
    }

    /// Get the risk kind for a function.
    /// Returns null if function is not in the registry.
    pub fn getRiskKind(func_name: []const u8) ?RiskKind {
        const sem = lookup(func_name) orelse return null;
        return sem.kind;
    }

    /// Get the severity for a function.
    /// Returns null if function is not in the registry.
    pub fn getSeverity(func_name: []const u8) ?Severity {
        const sem = lookup(func_name) orelse return null;
        return sem.severity;
    }

    /// Check if a function consumes ownership.
    /// Returns false if function is not in the registry.
    pub fn consumesOwnership(func_name: []const u8) bool {
        const sem = lookup(func_name) orelse return false;
        return sem.consumes_ownership;
    }

    /// Check if a function transfers ownership.
    /// Returns false if function is not in the registry.
    pub fn transfersOwnership(func_name: []const u8) bool {
        const sem = lookup(func_name) orelse return false;
        return sem.transfers_ownership;
    }

    /// Check if a function requires null check on its result.
    /// Returns false if function is not in the registry.
    pub fn requiresNullCheck(func_name: []const u8) bool {
        const sem = lookup(func_name) orelse return false;
        return sem.requires_null_check;
    }

    /// Check if a function requires taint checking on its arguments.
    /// Returns false if function is not in the registry.
    pub fn requiresTaintCheck(func_name: []const u8) bool {
        const sem = lookup(func_name) orelse return false;
        return sem.requires_taint_check;
    }

    /// Get description for a function.
    /// Returns null if function is not in the registry.
    pub fn getDescription(func_name: []const u8) ?[]const u8 {
        const sem = lookup(func_name) orelse return null;
        return sem.description;
    }

    /// Check if a function is a dangerous sink.
    /// Uses the registry first, then falls back to pattern matching.
    pub fn isDangerousSink(func_name: []const u8) bool {
        // Use registry for known functions
        if (lookup(func_name)) |sem| {
            return sem.requires_taint_check;
        }

        // Fallback: pattern matching for unknown functions
        const dangerous_patterns = &[_][]const u8{
            "system",
            "exec",
            "popen",
            "strcpy",
            "strcat",
            "sprintf",
            "gets",
            "printf",
            "fprintf",
            "snprintf",
            "memcpy",
            "memmove",
        };

        for (dangerous_patterns) |pattern| {
            if (std.mem.indexOf(u8, func_name, pattern) != null) {
                return true;
            }
        }
        return false;
    }

    /// Get confidence decay factor based on function semantics.
    /// Higher severity = higher decay (more confidence preserved for dangerous ops).
    /// Returns 0.95 as default for unknown functions.
    pub fn getConfidenceDecay(func_name: []const u8) f32 {
        if (getSeverity(func_name)) |severity| {
            return switch (severity) {
                .critical => 0.98, // Critical: preserve most confidence
                .high => 0.95, // High: standard decay
                .medium => 0.90, // Medium: slightly more decay
                .low => 0.85, // Low: more decay
            };
        }
        return 0.95; // Default decay
    }

    /// Get the count of Layer 1 functions.
    pub fn layer1Count() usize {
        return layer1.len;
    }

    /// Get the count of Layer 2 functions.
    pub fn layer2Count() usize {
        return layer2.len;
    }

    /// Get the count of Layer 3 functions.
    pub fn layer3Count() usize {
        return layer3.len;
    }

    /// Get the count of Layer 4 functions.
    pub fn layer4Count() usize {
        return layer4.len;
    }

    /// Get the count of Layer 5 (Zig) functions.
    pub fn layer5Count() usize {
        return layer5.len;
    }

    /// Get the count of Layer 6 (C++) functions.
    pub fn layer6Count() usize {
        return layer6.len;
    }

    /// Get total count of known functions.
    pub fn totalCount() usize {
        return layer1.len + layer2.len + layer3.len + layer4.len + layer5.len + layer6.len;
    }
};

// Unit tests

test "SemanticRegistry - RiskKind enum" {
    try std.testing.expectEqual(@as(usize, 13), @typeInfo(RiskKind).@"enum".fields.len);
}

test "SemanticRegistry - Severity enum" {
    try std.testing.expectEqual(@as(u8, 1), @intFromEnum(Severity.low));
    try std.testing.expectEqual(@as(u8, 2), @intFromEnum(Severity.medium));
    try std.testing.expectEqual(@as(u8, 3), @intFromEnum(Severity.high));
    try std.testing.expectEqual(@as(u8, 4), @intFromEnum(Severity.critical));
}

test "SemanticRegistry - Severity toString" {
    try std.testing.expectEqualStrings("LOW", Severity.low.toString());
    try std.testing.expectEqualStrings("MEDIUM", Severity.medium.toString());
    try std.testing.expectEqualStrings("HIGH", Severity.high.toString());
    try std.testing.expectEqualStrings("CRITICAL", Severity.critical.toString());
}

test "SemanticRegistry - lookup exact match" {
    const sem = SemanticRegistry.lookup("malloc").?;
    try std.testing.expectEqual(RiskKind.allocator, sem.kind);
    try std.testing.expectEqual(Severity.medium, sem.severity);
    try std.testing.expect(sem.transfers_ownership);
    try std.testing.expect(sem.requires_null_check);
}

test "SemanticRegistry - lookup contains match" {
    const sem = SemanticRegistry.lookup("std::boxed::Box<T>::into_raw").?;
    try std.testing.expectEqual(RiskKind.rust_ownership, sem.kind);
    try std.testing.expectEqual(Severity.high, sem.severity);
    try std.testing.expect(sem.consumes_ownership);
    try std.testing.expect(sem.transfers_ownership);
}

test "SemanticRegistry - lookup unknown function" {
    try std.testing.expect(SemanticRegistry.lookup("unknown_func") == null);
}

test "SemanticRegistry - isKnown" {
    try std.testing.expect(SemanticRegistry.isKnown("free"));
    try std.testing.expect(SemanticRegistry.isKnown("into_raw"));
    try std.testing.expect(!SemanticRegistry.isKnown("unknown_func"));
}

test "SemanticRegistry - getRiskKind" {
    try std.testing.expectEqual(RiskKind.command_exec, SemanticRegistry.getRiskKind("system").?);
    try std.testing.expectEqual(RiskKind.deallocator, SemanticRegistry.getRiskKind("free").?);
    try std.testing.expect(SemanticRegistry.getRiskKind("unknown") == null);
}

test "SemanticRegistry - getSeverity" {
    try std.testing.expectEqual(Severity.critical, SemanticRegistry.getSeverity("system").?);
    try std.testing.expectEqual(Severity.high, SemanticRegistry.getSeverity("free").?);
    try std.testing.expect(SemanticRegistry.getSeverity("unknown") == null);
}

test "SemanticRegistry - consumesOwnership" {
    try std.testing.expect(SemanticRegistry.consumesOwnership("free"));
    try std.testing.expect(!SemanticRegistry.consumesOwnership("malloc"));
    try std.testing.expect(!SemanticRegistry.consumesOwnership("unknown"));
}

test "SemanticRegistry - transfersOwnership" {
    try std.testing.expect(SemanticRegistry.transfersOwnership("malloc"));
    try std.testing.expect(!SemanticRegistry.transfersOwnership("free"));
    try std.testing.expect(!SemanticRegistry.transfersOwnership("unknown"));
}

test "SemanticRegistry - requiresNullCheck" {
    try std.testing.expect(SemanticRegistry.requiresNullCheck("malloc"));
    try std.testing.expect(!SemanticRegistry.requiresNullCheck("free"));
    try std.testing.expect(!SemanticRegistry.requiresNullCheck("unknown"));
}

test "SemanticRegistry - requiresTaintCheck" {
    try std.testing.expect(SemanticRegistry.requiresTaintCheck("system"));
    try std.testing.expect(SemanticRegistry.requiresTaintCheck("strcpy"));
    try std.testing.expect(!SemanticRegistry.requiresTaintCheck("malloc"));
    try std.testing.expect(!SemanticRegistry.requiresTaintCheck("unknown"));
}

test "SemanticRegistry - getDescription" {
    const desc = SemanticRegistry.getDescription("system").?;
    try std.testing.expect(std.mem.indexOf(u8, desc, "command injection") != null);
    try std.testing.expect(SemanticRegistry.getDescription("unknown") == null);
}

test "SemanticRegistry - counts" {
    try std.testing.expectEqual(@as(usize, 37), SemanticRegistry.layer1Count());
    try std.testing.expectEqual(@as(usize, 3), SemanticRegistry.layer2Count());
    try std.testing.expectEqual(@as(usize, 4), SemanticRegistry.layer3Count());
    try std.testing.expectEqual(@as(usize, 3), SemanticRegistry.layer4Count());
    try std.testing.expectEqual(@as(usize, 47), SemanticRegistry.totalCount());
}

test "SemanticRegistry - mmap/munmap" {
    const mmap_sem = SemanticRegistry.lookup("mmap").?;
    try std.testing.expectEqual(RiskKind.memory_map, mmap_sem.kind);
    try std.testing.expect(mmap_sem.transfers_ownership);
    try std.testing.expect(mmap_sem.requires_null_check);

    const munmap_sem = SemanticRegistry.lookup("munmap").?;
    try std.testing.expectEqual(RiskKind.memory_map, munmap_sem.kind);
    try std.testing.expect(munmap_sem.consumes_ownership);
}

test "SemanticRegistry - file I/O" {
    const fopen_sem = SemanticRegistry.lookup("fopen").?;
    try std.testing.expectEqual(RiskKind.file_io, fopen_sem.kind);
    try std.testing.expect(fopen_sem.transfers_ownership);

    const fclose_sem = SemanticRegistry.lookup("fclose").?;
    try std.testing.expectEqual(RiskKind.file_io, fclose_sem.kind);
    try std.testing.expect(fclose_sem.consumes_ownership);
}

test "SemanticRegistry - network I/O" {
    const socket_sem = SemanticRegistry.lookup("socket").?;
    try std.testing.expectEqual(RiskKind.network_io, socket_sem.kind);
    try std.testing.expect(socket_sem.transfers_ownership);

    const accept_sem = SemanticRegistry.lookup("accept").?;
    try std.testing.expectEqual(RiskKind.network_io, accept_sem.kind);
    try std.testing.expect(accept_sem.transfers_ownership);
}

test "SemanticRegistry - Go cgo patterns" {
    const malloc_sem = SemanticRegistry.lookup("C.malloc").?;
    try std.testing.expectEqual(RiskKind.go_cgo_alloc, malloc_sem.kind);
    try std.testing.expect(malloc_sem.transfers_ownership);

    const cstring_sem = SemanticRegistry.lookup("C.CString").?;
    try std.testing.expectEqual(RiskKind.go_cgo_alloc, cstring_sem.kind);

    const free_sem = SemanticRegistry.lookup("C.free").?;
    try std.testing.expectEqual(RiskKind.go_cgo_alloc, free_sem.kind);
    try std.testing.expect(free_sem.consumes_ownership);
}

test "SemanticRegistry - Swift FFI patterns" {
    const bytes_sem = SemanticRegistry.lookup("withUnsafeBytes").?;
    try std.testing.expectEqual(RiskKind.borrow_escaped, bytes_sem.kind);

    const ptr_sem = SemanticRegistry.lookup("UnsafeMutablePointer").?;
    try std.testing.expectEqual(RiskKind.allocator, ptr_sem.kind);
}

test "SemanticRegistry - as_ptr borrow escape" {
    const sem = SemanticRegistry.lookup("slice.as_ptr").?;
    try std.testing.expectEqual(RiskKind.borrow_escaped, sem.kind);
    try std.testing.expectEqual(Severity.medium, sem.severity);
    try std.testing.expect(!sem.consumes_ownership);
    try std.testing.expect(!sem.transfers_ownership);
}

test "SemanticRegistry - realloc special case" {
    const sem = SemanticRegistry.lookup("realloc").?;
    try std.testing.expectEqual(RiskKind.allocator, sem.kind);
    try std.testing.expect(sem.consumes_ownership);
    try std.testing.expect(sem.transfers_ownership);
}

test "SemanticRegistry - macOS platform variants" {
    // macOS uses \01_ prefix for some libc functions
    const sem_system = SemanticRegistry.lookup("\x01_system").?;
    try std.testing.expectEqual(RiskKind.command_exec, sem_system.kind);
    try std.testing.expectEqual(Severity.critical, sem_system.severity);

    // macOS uses __*_chk for fortified functions
    const sem_strcpy = SemanticRegistry.lookup("__strcpy_chk").?;
    try std.testing.expectEqual(RiskKind.unchecked_copy, sem_strcpy.kind);
    try std.testing.expectEqual(Severity.high, sem_strcpy.severity);

    const sem_sprintf = SemanticRegistry.lookup("__sprintf_chk").?;
    try std.testing.expectEqual(RiskKind.unchecked_copy, sem_sprintf.kind);
    try std.testing.expectEqual(Severity.high, sem_sprintf.severity);

    const sem_printf = SemanticRegistry.lookup("__printf_chk").?;
    try std.testing.expectEqual(RiskKind.format_string, sem_printf.kind);
    try std.testing.expectEqual(Severity.medium, sem_printf.severity);
}

test "SemanticRegistry - Linux platform variants" {
    // Linux uses standard libc names
    const sem_system = SemanticRegistry.lookup("system").?;
    try std.testing.expectEqual(RiskKind.command_exec, sem_system.kind);

    const sem_strcpy = SemanticRegistry.lookup("strcpy").?;
    try std.testing.expectEqual(RiskKind.unchecked_copy, sem_strcpy.kind);

    const sem_sprintf = SemanticRegistry.lookup("sprintf").?;
    try std.testing.expectEqual(RiskKind.unchecked_copy, sem_sprintf.kind);
}

test "SemanticRegistry - suffix match type" {
    // Test suffix matching for system variants
    try std.testing.expect(SemanticRegistry.isKnown("system"));
    try std.testing.expect(SemanticRegistry.isKnown("\x01_system"));
    try std.testing.expect(SemanticRegistry.isKnown("popen"));
    try std.testing.expect(SemanticRegistry.isKnown("\x01_popen"));
}

test "SemanticRegistry - contains match type" {
    // Test contains matching for fortified variants
    try std.testing.expect(SemanticRegistry.isKnown("strcpy"));
    try std.testing.expect(SemanticRegistry.isKnown("__strcpy_chk"));
    try std.testing.expect(SemanticRegistry.isKnown("sprintf"));
    try std.testing.expect(SemanticRegistry.isKnown("__sprintf_chk"));
    try std.testing.expect(SemanticRegistry.isKnown("printf"));
    try std.testing.expect(SemanticRegistry.isKnown("__printf_chk"));
}
