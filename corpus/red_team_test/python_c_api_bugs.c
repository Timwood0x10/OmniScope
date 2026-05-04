/**
 * Python C API Boundary Bug Test Cases
 *
 * Tests for Python C API FFI boundary issues:
 * - Return value NULL check missing
 * - GIL state management issues (cross-thread calls without Ensure/Release)
 * - Py_DECREF after use (UAF)
 * - PyTuple_New/PyList_New/PyDict_New without proper cleanup
 */

#include <Python.h>
#include <pthread.h>
#include <stdlib.h>
#include <string.h>

/* PY-01: Py_BuildValue returns NULL without check */
int PY_01_Py_BuildValue_Null_Check(const char* fmt, int x) {
    PyObject* obj = Py_BuildValue("(i)", x);
    // BUG: Py_BuildValue can return NULL on memory error
    PyObject* result = PyTuple_Pack(1, obj);
    // If obj is NULL, PyTuple_Pack crashes or returns NULL
    Py_DECREF(obj);
    Py_DECREF(result);
    return 0;
}

/* PY-02: PyArg_ParseTuple return value not checked */
int PY_02_PyArg_ParseTuple_No_Check(PyObject* args) {
    int x, y;
    // BUG: Return value not checked - should be 1 on success, 0 on error
    PyArg_ParseTuple(args, "ii", &x, &y);
    return x + y;
}

/* PY-03: PyTuple_New returns NULL without check */
PyObject* PY_03_PyTuple_New_Null_Check(int size) {
    PyObject* tuple = PyTuple_New(size);
    // BUG: PyTuple_New returns NULL if size invalid or OOM
    for (int i = 0; i < size; i++) {
        PyTuple_SET_ITEM(tuple, i, PyLong_FromLong(i));
    }
    return tuple;
}

/* PY-04: PyList_New returns NULL without check */
PyObject* PY_04_PyList_New_Null_Check(int size) {
    PyObject* list = PyList_New(size);
    // BUG: PyList_New returns NULL on error
    for (int i = 0; i < size; i++) {
        PyList_SET_ITEM(list, i, PyLong_FromLong(i));
    }
    return list;
}

/* PY-05: Cross-thread call without GIL */
void* thread_worker(void* arg) {
    PyObject* callable = (PyObject*)arg;
    // BUG: Called without PyGILState_Ensure - GIL not held
    // Should wrap in PyGILState_Ensure/PyGILState_Release
    PyObject* result = PyObject_Call(callable, PyTuple_New(0), NULL);
    Py_XDECREF(result);
    return NULL;
}

void PY_05_Call_Without_GIL(PyObject* callable) {
    pthread_t tid;
    pthread_create(&tid, NULL, thread_worker, callable);
    pthread_detach(tid);
}

/* PY-06: Py_DECREF then use (UAF) */
void PY_06_Py_DECREF_Use_After(PyObject* obj) {
    Py_INCREF(obj);
    Py_DECREF(obj);
    // BUG: obj may be deallocated (refcount reached 0)
    // Accessing it is UAF
    printf("PyObject refcount: %ld\n", obj->ob_refcnt);
}

/* PY-07: PyObject_CallObject returns new reference not checked */
int PY_07_PyObject_CallObject_No_Check(PyObject* callable) {
    PyObject* result = PyObject_CallObject(callable, NULL);
    // BUG: Returns new reference, can be NULL on error
    // Not checking leads to NULL dereference
    long val = PyLong_AsLong(result);
    Py_XDECREF(result);
    return (int)val;
}

/* PY-08: PyModule_Create returns NULL without check */
PyObject* PY_08_PyModule_Create_Null_Check(void) {
    PyObject* module = PyModule_Create(NULL);
    // BUG: PyModule_Create can return NULL
    PyObject* dict = PyModule_GetDict(module);
    // Crash if module is NULL
    return module;
}

/* PY-09: PyImport_ImportModule returns NULL without check */
PyObject* PY_09_PyImport_ImportModule_Null_Check(const char* name) {
    PyObject* module = PyImport_ImportModule(name);
    // BUG: Returns NULL if import fails, sets PyErr
    // Not checking leads to issues when using module
    return module;
}

/* PY-10: PyCapsule_GetPointer returns NULL without check */
void* PY_10_PyCapsule_GetPointer_Null_Check(PyObject* capsule, const char* name) {
    void* ptr = PyCapsule_GetPointer(capsule, name);
    // BUG: Returns NULL on error, sets PyErr
    // Using ptr without check causes crash
    return ptr;
}

/* PY-11: PyCapsule_SetDestructor before use */
void PY_11_PyCapsule_Destructor_Use_After_Set(PyObject* capsule) {
    PyCapsule_SetDestructor(capsule, NULL);
    // BUG: Setting destructor to NULL doesn't free capsule
    // If capsule held resources, they're leaked
    // Should call PyCapsule_SetDestructor with proper destructor first
}

/* PY-12: PyEval_CallObject with wrong args */
int PY_12_PyEval_CallObject_Wrong_Args(PyObject* func) {
    PyObject* args = Py_BuildValue("(i)", 42);
    PyObject* result = PyEval_CallObject(func, args);
    // BUG: If func expects different args, behavior undefined
    // Should use PyArg_ParseTuple to validate args
    Py_XDECREF(args);
    Py_XDECREF(result);
    return 0;
}
