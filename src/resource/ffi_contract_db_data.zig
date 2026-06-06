//! Built-in FFI Contract Data (embedded at compile time)
//!
//! Contains the built-in library contract definitions used by FFIContractDB.
//! This data is embedded at comptime — no file I/O required.
//! Separated from ffi_contract_db.zig to keep core logic and data concerns clean.

const std = @import("std");
const cdb = @import("ffi_contract_db.zig");

const OwnershipModel = cdb.OwnershipModel;
const AllocPairRule = cdb.AllocPairRule;
const ManagedTypeInfo = cdb.ManagedTypeInfo;
const LibraryContract = cdb.LibraryContract;

/// Returns the full set of built-in library contracts.
/// This data is embedded at comptime — no file I/O required.
pub fn builtinLibraries() []const LibraryContract {
    return &[_]LibraryContract{
        // ── OpenSSL / BoringSSL ──────────────────────────────────────
        .{
            .name = "openssl",
            .description = "BoringSSL/OpenSSL object lifecycle",
            .error_prone = true,
            .pairs = &[_]AllocPairRule{
                .{
                    .name = "SSL_CTX",
                    .alloc_funcs = &[_][]const u8{ "SSL_CTX_new", "TLS_method", "TLS_server_method", "TLS_client_method" },
                    .release_funcs = &[_][]const u8{"SSL_CTX_free"},
                    .ownership = .caller,
                    .confidence = 0.95,
                },
                .{
                    .name = "SSL",
                    .alloc_funcs = &[_][]const u8{ "SSL_new", "SSL_dup" },
                    .release_funcs = &[_][]const u8{"SSL_free"},
                    .ownership = .caller,
                    .confidence = 0.95,
                },
                .{
                    .name = "BIO",
                    .alloc_funcs = &[_][]const u8{ "BIO_new", "BIO_new_file", "BIO_new_mem_buf", "BIO_s_mem" },
                    .release_funcs = &[_][]const u8{ "BIO_free", "BIO_free_all" },
                    .ownership = .caller,
                },
                .{
                    .name = "X509",
                    .alloc_funcs = &[_][]const u8{ "PEM_read_bio_X509", "PEM_read_X509", "d2i_X509", "X509_new" },
                    .release_funcs = &[_][]const u8{"X509_free"},
                    .ownership = .caller,
                },
                .{
                    .name = "EVP_PKEY",
                    .alloc_funcs = &[_][]const u8{ "PEM_read_bio_PrivateKey", "PEM_read_bio_PUBKEY", "d2i_AutoPrivateKey" },
                    .release_funcs = &[_][]const u8{"EVP_PKEY_free"},
                    .ownership = .caller,
                },
                .{
                    .name = "EVP_CIPHER_CTX",
                    .alloc_funcs = &[_][]const u8{"EVP_CIPHER_CTX_new"},
                    .release_funcs = &[_][]const u8{"EVP_CIPHER_CTX_free"},
                    .ownership = .caller,
                },
                .{
                    .name = "EVP_MD_CTX",
                    .alloc_funcs = &[_][]const u8{"EVP_MD_CTX_new"},
                    .release_funcs = &[_][]const u8{"EVP_MD_CTX_free"},
                    .ownership = .caller,
                },
                .{
                    .name = "RSA",
                    .alloc_funcs = &[_][]const u8{"RSA_new"},
                    .release_funcs = &[_][]const u8{"RSA_free"},
                    .ownership = .caller,
                },
                .{
                    .name = "BIGNUM",
                    .alloc_funcs = &[_][]const u8{"BN_new"},
                    .release_funcs = &[_][]const u8{"BN_free"},
                    .ownership = .caller,
                },
            },
            .managed_types = &[_]ManagedTypeInfo{
                .{
                    .type_patterns = &[_][]const u8{"OPENSSL_mem_fn"},
                    .model = .custom,
                },
            },
        },

        // ── SQLite ───────────────────────────────────────────────────
        .{
            .name = "sqlite",
            .description = "SQLite database handle and statement management",
            .error_prone = true,
            .pairs = &[_]AllocPairRule{
                .{
                    .name = "database_connection",
                    .alloc_funcs = &[_][]const u8{ "sqlite3_open", "sqlite3_open_v2", "sqlite3_open16" },
                    .release_funcs = &[_][]const u8{ "sqlite3_close", "sqlite3_close_v2" },
                    .ownership = .caller,
                },
                .{
                    .name = "prepared_statement",
                    .alloc_funcs = &[_][]const u8{ "sqlite3_prepare_v2", "sqlite3_prepare16", "sqlite3_prepare_v3" },
                    .release_funcs = &[_][]const u8{"sqlite3_finalize"},
                    .ownership = .caller,
                    .confidence = 0.98,
                },
                .{
                    .name = "blob",
                    .alloc_funcs = &[_][]const u8{ "sqlite3_blob_open", "sqlite3_blob_reopen" },
                    .release_funcs = &[_][]const u8{"sqlite3_blob_close"},
                    .ownership = .caller,
                },
                .{
                    .name = "sqlite_malloc",
                    .alloc_funcs = &[_][]const u8{ "sqlite3_malloc", "sqlite3_realloc" },
                    .release_funcs = &[_][]const u8{"sqlite3_free"},
                    .ownership = .caller,
                },
            },
        },

        // ── POSIX ────────────────────────────────────────────────────
        .{
            .name = "posix",
            .description = "POSIX file descriptors and memory mappings",
            .pairs = &[_]AllocPairRule{
                .{
                    .name = "file_descriptor",
                    .alloc_funcs = &[_][]const u8{ "open", "openat", "creat", "socket", "accept", "dup", "fcntl" },
                    .release_funcs = &[_][]const u8{"close"},
                    .ownership = .caller,
                },
                .{
                    .name = "memory_mapping",
                    .alloc_funcs = &[_][]const u8{ "mmap", "mmap64", "shm_open" },
                    .release_funcs = &[_][]const u8{ "munmap", "shm_unlink" },
                    .ownership = .caller,
                },
                .{
                    .name = "directory_stream",
                    .alloc_funcs = &[_][]const u8{"opendir"},
                    .release_funcs = &[_][]const u8{"closedir"},
                    .ownership = .caller,
                },
            },
        },

        // ── GLib ─────────────────────────────────────────────────────
        .{
            .name = "glib",
            .description = "GLib memory management (GNOME/GTK) - enhanced",
            .error_prone = true,
            .pairs = &[_]AllocPairRule{
                // Enhanced memory allocation rules
                .{
                    .name = "glib_memory",
                    .alloc_funcs = &[_][]const u8{
                        "g_malloc",
                        "g_malloc0",
                        "g_realloc",
                        "g_strdup",
                        "g_strdup_printf",
                        "g_strndup",
                        "g_try_malloc",
                        "g_try_malloc0",
                        "g_new",
                        "g_new0",
                        "g_slice_alloc",
                        "g_slice_copy",
                    },
                    .release_funcs = &[_][]const u8{
                        "g_free",
                        "g_slice_free1",
                        "g_slice_free_chain",
                    },
                    .ownership = .caller,
                    .confidence = 0.93,
                },
                // String operations
                .{
                    .name = "glib_string",
                    .alloc_funcs = &[_][]const u8{ "g_strdup", "g_strndup", "g_build_path", "g_build_filename" },
                    .release_funcs = &[_][]const u8{"g_free"},
                    .ownership = .caller,
                },
                // GLib object system (reference counted)
                .{
                    .name = "glib_object",
                    .alloc_funcs = &[_][]const u8{
                        "g_object_new",
                        "g_object_ref",
                        "g_object_ref_sink",
                    },
                    .release_funcs = &[_][]const u8{
                        "g_object_unref",
                    },
                    .ownership = .caller,
                    .confidence = 0.91,
                },
            },
        },

        // ── JavaScriptCore (WebKit) ──────────────────────────────────
        .{
            .name = "javascriptcore",
            .description = "WebKit JavaScriptCore GC-managed objects",
            .pairs = &[_]AllocPairRule{},
            .managed_types = &[_]ManagedTypeInfo{
                .{
                    .type_patterns = &[_][]const u8{ "JSObject", "JSString", "JSContextRef", "JSValueRef", "JSPropertyNameArrayRef", "JSObjectMake", "JSStringCreateWithUTF8CString", "JSValueMakeString", "JSValueProtect", "JSValueRetain" },
                    .model = .gc,
                    .retain_funcs = &[_][]const u8{ "JSValueProtect", "JSValueRetain", "JSObjectSetPrivate" },
                    .release_funcs = &[_][]const u8{"JSValueUnprotect"},
                },
            },
        },

        // ── libuv ────────────────────────────────────────────────────
        .{
            .name = "libuv",
            .description = "libuv handles (event loop handles)",
            .pairs = &[_]AllocPairRule{
                .{
                    .name = "tcp",
                    .alloc_funcs = &[_][]const u8{ "uv_tcp_init", "uv_tcp_init_ex" },
                    .release_funcs = &[_][]const u8{"uv_close"},
                    .ownership = .caller,
                },
                .{
                    .name = "timer",
                    .alloc_funcs = &[_][]const u8{"uv_timer_init"},
                    .release_funcs = &[_][]const u8{"uv_close"},
                    .ownership = .caller,
                },
                .{
                    .name = "async_handle",
                    .alloc_funcs = &[_][]const u8{"uv_async_init"},
                    .release_funcs = &[_][]const u8{"uv_close"},
                    .ownership = .caller,
                },
            },
        },

        // ── zlib ──────────────────────────────────────────────────────
        .{
            .name = "zlib",
            .description = "zlib compression stream",
            .pairs = &[_]AllocPairRule{
                .{
                    .name = "stream",
                    .alloc_funcs = &[_][]const u8{ "deflateInit_", "deflateInit2_", "inflateInit_", "inflateInit2_" },
                    .release_funcs = &[_][]const u8{ "deflateEnd", "inflateEnd" },
                    .ownership = .caller,
                },
                .{
                    .name = "gz_file",
                    .alloc_funcs = &[_][]const u8{ "gzopen", "gzdopen", "gzbuffer" },
                    .release_funcs = &[_][]const u8{"gzclose"},
                    .ownership = .caller,
                },
            },
        },

        // ── Python C API ─────────────────────────────────────────────
        .{
            .name = "python_capi",
            .description = "Python C API reference counting (comprehensive)",
            .error_prone = true,
            .pairs = &[_]AllocPairRule{
                // Object creation functions (return owned references - must Py_DECREF)
                .{
                    .name = "py_object_new",
                    .alloc_funcs = &[_][]const u8{
                        "PyList_New",
                        "PyDict_New",
                        "PyTuple_New",
                        "PySet_New",
                        "PyFrozenSet_New",
                        "PyBytes_FromString",
                        "PyBytes_FromStringAndSize",
                        "PyUnicode_FromString",
                        "PyUnicode_Decode",
                        "PyLong_FromLong",
                        "PyFloat_FromDouble",
                        "Py_BuildValue",
                    },
                    .release_funcs = &[_][]const u8{"Py_DECREF"},
                    .ownership = .caller,
                    .confidence = 0.92,
                },
                // Borrowed reference functions (do NOT call Py_DECREF!)
                .{
                    .name = "py_borrowed_ref",
                    .alloc_funcs = &[_][]const u8{
                        "PyList_GetItem",
                        "PyDict_GetItem",
                        "PyDict_GetItemString",
                        "PyTuple_GetItem",
                        "PySequence_GetItem",
                        "PyImport_ImportModule",
                        "PyImport_AddModule",
                        "PyObject_GetAttr",
                        "PyObject_GetAttrString",
                    },
                    .release_funcs = &[_][]const u8{},
                    .ownership = .borrowed,
                    .confidence = 0.95,
                },
                // GIL operations (scoped resource)
                .{
                    .name = "py_gil",
                    .alloc_funcs = &[_][]const u8{"PyGILState_Ensure"},
                    .release_funcs = &[_][]const u8{"PyGILState_Release"},
                    .ownership = .caller,
                    .confidence = 0.98,
                },
                // Legacy Python C API object creation
                .{
                    .name = "py_object_legacy",
                    .alloc_funcs = &[_][]const u8{ "PyBytes_FromString", "PyBytes_FromStringAndSize", "PyTuple_New", "PyList_New", "PyDict_New" },
                    .release_funcs = &[_][]const u8{ "Py_DECREF", "Py_XDECREF" },
                    .ownership = .caller,
                },
                // Legacy borrowed references
                .{
                    .name = "py_borrowed_legacy",
                    .alloc_funcs = &[_][]const u8{ "PyList_GetItem", "PyDict_GetItem", "PyTuple_GetItem", "PyBytes_AsString" },
                    .release_funcs = &[_][]const u8{},
                    .ownership = .borrowed,
                },
            },
        },

        // ── JNI (Java Native Interface) ──────────────────────────────
        .{
            .name = "jni",
            .description = "JNI local/global reference management",
            .error_prone = true,
            .pairs = &[_]AllocPairRule{
                // JNI GlobalRef lifecycle (must be explicitly deleted)
                .{
                    .name = "jni_global_ref",
                    .alloc_funcs = &[_][]const u8{"NewGlobalRef"},
                    .release_funcs = &[_][]const u8{"DeleteGlobalRef"},
                    .ownership = .caller,
                    .confidence = 0.95,
                },
                // JNI LocalRef lifecycle (auto-freed, but can be explicit)
                .{
                    .name = "jni_local_ref",
                    .alloc_funcs = &[_][]const u8{
                        "NewLocalRef",
                        "FindClass",
                        "CallObjectMethod",
                        "CallStaticObjectMethod",
                        "GetObjectField",
                        "NewStringUTF",
                    },
                    .release_funcs = &[_][]const u8{"DeleteLocalRef"},
                    .ownership = .gc,
                    .confidence = 0.90,
                },
                // JNI String UTF chars (must be released)
                .{
                    .name = "jni_string_utf_chars",
                    .alloc_funcs = &[_][]const u8{"GetStringUTFChars"},
                    .release_funcs = &[_][]const u8{"ReleaseStringUTFChars"},
                    .ownership = .caller,
                    .confidence = 0.92,
                },
                // JNI ByteArray elements (must be released)
                .{
                    .name = "jni_byte_array_elements",
                    .alloc_funcs = &[_][]const u8{"GetByteArrayElements"},
                    .release_funcs = &[_][]const u8{"ReleaseByteArrayElements"},
                    .ownership = .caller,
                    .confidence = 0.92,
                },
                // JNI CharArray elements (must be released)
                .{
                    .name = "jni_char_array_elements",
                    .alloc_funcs = &[_][]const u8{"GetCharArrayElements"},
                    .release_funcs = &[_][]const u8{"ReleaseCharArrayElements"},
                    .ownership = .caller,
                    .confidence = 0.92,
                },
                // JNI ShortArray elements (must be released)
                .{
                    .name = "jni_short_array_elements",
                    .alloc_funcs = &[_][]const u8{"GetShortArrayElements"},
                    .release_funcs = &[_][]const u8{"ReleaseShortArrayElements"},
                    .ownership = .caller,
                    .confidence = 0.92,
                },
                // JNI IntArray elements (must be released)
                .{
                    .name = "jni_int_array_elements",
                    .alloc_funcs = &[_][]const u8{"GetIntArrayElements"},
                    .release_funcs = &[_][]const u8{"ReleaseIntArrayElements"},
                    .ownership = .caller,
                    .confidence = 0.92,
                },
                // JNI LongArray elements (must be released)
                .{
                    .name = "jni_long_array_elements",
                    .alloc_funcs = &[_][]const u8{"GetLongArrayElements"},
                    .release_funcs = &[_][]const u8{"ReleaseLongArrayElements"},
                    .ownership = .caller,
                    .confidence = 0.92,
                },
                // JNI FloatArray elements (must be released)
                .{
                    .name = "jni_float_array_elements",
                    .alloc_funcs = &[_][]const u8{"GetFloatArrayElements"},
                    .release_funcs = &[_][]const u8{"ReleaseFloatArrayElements"},
                    .ownership = .caller,
                    .confidence = 0.92,
                },
                // JNI DoubleArray elements (must be released)
                .{
                    .name = "jni_double_array_elements",
                    .alloc_funcs = &[_][]const u8{"GetDoubleArrayElements"},
                    .release_funcs = &[_][]const u8{"ReleaseDoubleArrayElements"},
                    .ownership = .caller,
                    .confidence = 0.92,
                },
                // JNI BooleanArray elements (must be released)
                .{
                    .name = "jni_boolean_array_elements",
                    .alloc_funcs = &[_][]const u8{"GetBooleanArrayElements"},
                    .release_funcs = &[_][]const u8{"ReleaseBooleanArrayElements"},
                    .ownership = .caller,
                    .confidence = 0.92,
                },
                // JNI Thread attachment (must be detached)
                .{
                    .name = "jni_thread_attachment",
                    .alloc_funcs = &[_][]const u8{"AttachCurrentThread"},
                    .release_funcs = &[_][]const u8{"DetachCurrentThread"},
                    .ownership = .caller,
                    .confidence = 0.95,
                },
                // JNI arrays allocation (local refs, GC-managed)
                .{
                    .name = "jni_arrays",
                    .alloc_funcs = &[_][]const u8{
                        "NewByteArray",
                        "NewCharArray",
                        "NewShortArray",
                        "NewIntArray",
                        "NewLongArray",
                        "NewFloatArray",
                        "NewDoubleArray",
                        "NewBooleanArray",
                        "NewObjectArray",
                    },
                    .release_funcs = &[_][]const u8{},
                    .ownership = .gc,
                    .confidence = 0.88,
                },
            },
        },

        // ── mimalloc ──────────────────────────────────────────────────
        .{
            .name = "mimalloc",
            .description = "mimalloc - Bun's underlying memory allocator",
            .pairs = &[_]AllocPairRule{
                .{
                    .name = "memory",
                    .alloc_funcs = &[_][]const u8{ "mi_malloc", "mi_zalloc", "mi_realloc", "mi_heap_malloc", "mi_heap_zalloc", "mi_heap_realloc" },
                    .release_funcs = &[_][]const u8{ "mi_free", "mi_heap_free" },
                    .ownership = .caller,
                },
            },
        },
    };
}
