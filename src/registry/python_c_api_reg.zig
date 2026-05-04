const std = @import("std");
const types = @import("types.zig");

pub const python_c_api_functions = [_]types.FunctionSemantics{
    .{ .pattern = "Py_Initialize", .match_type = .exact, .kind = .python_c_api, .severity = .medium, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Initialize Python interpreter - call once at startup" },
    .{ .pattern = "Py_Finalize", .match_type = .exact, .kind = .python_c_api, .severity = .medium, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Finalize Python interpreter - call once at shutdown" },
    .{ .pattern = "Py_IncRef", .match_type = .exact, .kind = .python_c_api, .severity = .medium, .consumes_ownership = false, .transfers_ownership = true, .requires_null_check = false, .requires_taint_check = false, .description = "Increment Python object reference count" },
    .{ .pattern = "Py_DecRef", .match_type = .exact, .kind = .python_c_api, .severity = .high, .consumes_ownership = true, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Decrement Python object reference count - use-after-free if called on freed object" },
    .{ .pattern = "Py_INCREF", .match_type = .exact, .kind = .python_c_api, .severity = .medium, .consumes_ownership = false, .transfers_ownership = true, .requires_null_check = false, .requires_taint_check = false, .description = "Increment Python object reference count (legacy macro)" },
    .{ .pattern = "Py_DECREF", .match_type = .exact, .kind = .python_c_api, .severity = .high, .consumes_ownership = true, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Decrement Python object reference count (legacy macro)" },
    .{ .pattern = "Py_XINCREF", .match_type = .exact, .kind = .python_c_api, .severity = .medium, .consumes_ownership = false, .transfers_ownership = true, .requires_null_check = false, .requires_taint_check = false, .description = "Increment reference count (NULL-safe)" },
    .{ .pattern = "Py_XDECREF", .match_type = .exact, .kind = .python_c_api, .severity = .high, .consumes_ownership = true, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Decrement reference count (NULL-safe)" },
    .{ .pattern = "Py_BuildValue", .match_type = .exact, .kind = .python_c_api, .severity = .medium, .consumes_ownership = false, .transfers_ownership = true, .requires_null_check = true, .requires_taint_check = false, .description = "Create Python object from C value - returns new reference, check for NULL" },
    .{ .pattern = "PyArg_ParseTuple", .match_type = .exact, .kind = .python_c_api, .severity = .medium, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = true, .requires_taint_check = false, .description = "Parse Python tuple arguments - returns false on error" },
    .{ .pattern = "PyArg_ParseKeywords", .match_type = .exact, .kind = .python_c_api, .severity = .medium, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = true, .requires_taint_check = false, .description = "Parse Python keyword arguments - returns false on error" },
    .{ .pattern = "PyObject_Call", .match_type = .exact, .kind = .python_c_api, .severity = .medium, .consumes_ownership = false, .transfers_ownership = true, .requires_null_check = true, .requires_taint_check = false, .description = "Call Python callable - returns new reference, check for NULL" },
    .{ .pattern = "PyObject_CallObject", .match_type = .exact, .kind = .python_c_api, .severity = .medium, .consumes_ownership = false, .transfers_ownership = true, .requires_null_check = true, .requires_taint_check = false, .description = "Call Python object - returns new reference, check for NULL" },
    .{ .pattern = "PyObject_CallFunction", .match_type = .exact, .kind = .python_c_api, .severity = .medium, .consumes_ownership = false, .transfers_ownership = true, .requires_null_check = true, .requires_taint_check = false, .description = "Call Python function - returns new reference, check for NULL" },
    .{ .pattern = "PyModule_Create", .match_type = .exact, .kind = .python_c_api, .severity = .medium, .consumes_ownership = false, .transfers_ownership = true, .requires_null_check = true, .requires_taint_check = false, .description = "Create Python module - returns new reference, check for NULL" },
    .{ .pattern = "PyImport_ImportModule", .match_type = .exact, .kind = .python_c_api, .severity = .medium, .consumes_ownership = false, .transfers_ownership = true, .requires_null_check = true, .requires_taint_check = false, .description = "Import Python module - returns new reference, check for NULL" },
    .{ .pattern = "PyImport_Import", .match_type = .exact, .kind = .python_c_api, .severity = .medium, .consumes_ownership = false, .transfers_ownership = true, .requires_null_check = true, .requires_taint_check = false, .description = "Import Python module (object form) - returns new reference, check for NULL" },
    .{ .pattern = "PyErr_SetString", .match_type = .exact, .kind = .python_c_api, .severity = .low, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Set Python error - indicates exception state" },
    .{ .pattern = "PyErr_Occurred", .match_type = .exact, .kind = .python_c_api, .severity = .medium, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Check if error occurred - returns NULL or exception object" },
    .{ .pattern = "PyErr_Fetch", .match_type = .exact, .kind = .python_c_api, .severity = .medium, .consumes_ownership = false, .transfers_ownership = true, .requires_null_check = false, .requires_taint_check = false, .description = "Fetch and clear error - returns error indicators" },
    .{ .pattern = "PyErr_Restore", .match_type = .exact, .kind = .python_c_api, .severity = .medium, .consumes_ownership = true, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Restore error state - consumes references" },
    .{ .pattern = "PyGILState_Ensure", .match_type = .exact, .kind = .python_c_api, .severity = .high, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Ensure GIL is held - must PyGILState_Release, deadlock risk if nested" },
    .{ .pattern = "PyGILState_Release", .match_type = .exact, .kind = .python_c_api, .severity = .high, .consumes_ownership = true, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Release GIL - paired with PyGILState_Ensure" },
    .{ .pattern = "PyEval_CallObject", .match_type = .exact, .kind = .python_c_api, .severity = .medium, .consumes_ownership = false, .transfers_ownership = true, .requires_null_check = true, .requires_taint_check = false, .description = "Call callable with args - returns new reference, check for NULL" },
    .{ .pattern = "PyEval_InitThreads", .match_type = .exact, .kind = .python_c_api, .severity = .medium, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Initialize thread state - deprecated in Python 3.7+" },
    .{ .pattern = "PyList_New", .match_type = .exact, .kind = .python_c_api, .severity = .medium, .consumes_ownership = false, .transfers_ownership = true, .requires_null_check = true, .requires_taint_check = false, .description = "Create new Python list - returns new reference, check for NULL" },
    .{ .pattern = "PyDict_New", .match_type = .exact, .kind = .python_c_api, .severity = .medium, .consumes_ownership = false, .transfers_ownership = true, .requires_null_check = true, .requires_taint_check = false, .description = "Create new Python dict - returns new reference, check for NULL" },
    .{ .pattern = "PyTuple_New", .match_type = .exact, .kind = .python_c_api, .severity = .medium, .consumes_ownership = false, .transfers_ownership = true, .requires_null_check = true, .requires_taint_check = false, .description = "Create new Python tuple - returns new reference, check for NULL" },
    .{ .pattern = "PyTuple_Pack", .match_type = .exact, .kind = .python_c_api, .severity = .medium, .consumes_ownership = false, .transfers_ownership = true, .requires_null_check = true, .requires_taint_check = false, .description = "Create Python tuple from C values - returns new reference, check for NULL" },
    .{ .pattern = "PyLong_AsLong", .match_type = .exact, .kind = .python_c_api, .severity = .medium, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Convert Python int to C long - check PyErr_Occurred on error" },
    .{ .pattern = "PyLong_FromLong", .match_type = .exact, .kind = .python_c_api, .severity = .medium, .consumes_ownership = false, .transfers_ownership = true, .requires_null_check = true, .requires_taint_check = false, .description = "Create Python int from C long - returns new reference, check for NULL" },
    .{ .pattern = "PyFloat_AsDouble", .match_type = .exact, .kind = .python_c_api, .severity = .medium, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Convert Python float to C double - check PyErr_Occurred on error" },
    .{ .pattern = "PyCapsule_New", .match_type = .exact, .kind = .python_c_api, .severity = .medium, .consumes_ownership = false, .transfers_ownership = true, .requires_null_check = true, .requires_taint_check = false, .description = "Create capsule (opaque pointer wrapper) - returns new reference" },
    .{ .pattern = "PyCapsule_GetPointer", .match_type = .exact, .kind = .python_c_api, .severity = .medium, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = true, .requires_taint_check = false, .description = "Get pointer from capsule - check for NULL, validate capsule name" },
    .{ .pattern = "PyCapsule_SetDestructor", .match_type = .exact, .kind = .python_c_api, .severity = .medium, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = true, .requires_taint_check = false, .description = "Set capsule destructor - destructor called when capsule freed" },
};

test "python_c_api_reg: function count" {
    try std.testing.expectEqual(@as(usize, 35), python_c_api_functions.len);
}

test "python_c_api_reg: Py_INCREF/Py_DECREF pairs" {
    inline for (python_c_api_functions) |entry| {
        const name = @as([]const u8, entry.pattern);
        if (std.mem.eql(u8, name, "Py_IncRef") or std.mem.eql(u8, name, "Py_INCREF")) {
            try std.testing.expectEqual(@as(bool, true), entry.transfers_ownership);
            try std.testing.expectEqual(@as(bool, false), entry.consumes_ownership);
        }
        if (std.mem.eql(u8, name, "Py_DecRef") or std.mem.eql(u8, name, "Py_DECREF")) {
            try std.testing.expectEqual(@as(bool, true), entry.consumes_ownership);
            try std.testing.expectEqual(@as(bool, false), entry.transfers_ownership);
        }
    }
}

test "python_c_api_reg: GIL pairs" {
    inline for (python_c_api_functions) |entry| {
        const name = @as([]const u8, entry.pattern);
        if (std.mem.eql(u8, name, "PyGILState_Ensure")) {
            try std.testing.expectEqual(types.Severity.high, entry.severity);
        }
        if (std.mem.eql(u8, name, "PyGILState_Release")) {
            try std.testing.expectEqual(@as(bool, true), entry.consumes_ownership);
        }
    }
}
