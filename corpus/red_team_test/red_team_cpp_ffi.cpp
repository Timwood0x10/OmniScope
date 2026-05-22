/**
 * OmniScope Red Team — C++ Exception & RAII Bug Test Cases
 *
 * Simulates bugs that occur at C++ FFI boundaries involving:
 *   - Exception safety violations
 *   - new/delete mismatches
 *   - RAII across FFI boundaries
 *   - Virtual destructor issues
 *   - Smart pointer misuse with FFI
 */

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <new>

/* FFI declarations */
extern "C" {
    void* c_ffi_alloc(int size);
    void  c_ffi_free(void* ptr);
    void  c_ffi_register_callback(void (*cb)(void*, int), void* ctx);
    void  c_ffi_trigger_callback();
    void  c_ffi_store_pointer(const void* p);
    void* c_ffi_retrieve_pointer();
}

/* ================================================================
 * CPP-BUG-01: new[] / delete mismatch
 *
 * Allocating with new[] but deleting with delete (not delete[]).
 * This is undefined behavior.
 *
 * Expected: buffer_overflow (CWE-120)
 * ================================================================ */
void cpp_bug_01_new_array_delete_mismatch() {
    int* arr = new int[100];

    for (int i = 0; i < 100; i++) {
        arr[i] = i;
    }

    printf("CPP-BUG-01: arr[50] = %d\n", arr[50]);

    delete arr;  // [BUG] Should be delete[] arr
    // Only first element's destructor called, rest leaked
}

/* ================================================================
 * CPP-BUG-02: Exception thrown through C function
 *
 * C functions don't understand C++ exceptions. Throwing through
 * a C function boundary causes undefined behavior.
 *
 * Expected: undefined_behavior
 * ================================================================ */
void cpp_bug_02_throw_through_c() {
    /* Simulate: C callback that doesn't expect exceptions */
    try {
        int* ptr = (int*)c_ffi_alloc(sizeof(int));
        if (!ptr) {
            throw std::bad_alloc();  // [BUG] Exception in C context
        }
        *ptr = 42;
        c_ffi_free(ptr);
    } catch (...) {
        printf("CPP-BUG-02: caught exception\n");
    }
}

/* ================================================================
 * CPP-BUG-03: FFI pointer in unique_ptr with wrong deleter
 *
 * Wrapping a C-allocated pointer in unique_ptr with default
 * deleter (delete) instead of the correct C free function.
 *
 * Expected: cross_language_free (CWE-763)
 * ================================================================ */
#include <memory>

void cpp_bug_03_wrong_deleter() {
    void* raw = c_ffi_alloc(128);

    // [BUG] Using delete instead of c_ffi_free
    std::unique_ptr<char> wrong_ptr((char*)raw);
    // unique_ptr default deleter calls delete, not c_ffi_free
    // This is cross-language free mismatch
}

/* ================================================================
 * CPP-BUG-04: Virtual destructor missing, delete through base
 *
 * Deleting a derived class through base pointer without virtual
 * destructor causes undefined behavior (partial destruction).
 *
 * Expected: memory_leak (CWE-401)
 * ================================================================ */
class Base {
public:
    int base_data;
    // [BUG] No virtual destructor
    ~Base() { printf("Base::~Base()\n"); }
};

class Derived : public Base {
public:
    char* derived_data;

    Derived() {
        derived_data = new char[256];
        strcpy(derived_data, "derived allocation");
    }

    ~Derived() {
        printf("Derived::~Derived()\n");
        delete[] derived_data;
    }
};

void cpp_bug_04_missing_virtual_destructor() {
    Base* obj = new Derived();

    // [BUG] Deleting derived through base without virtual dtor
    // Derived::~Derived() is never called → derived_data leaks
    delete obj;
}

/* ================================================================
 * CPP-BUG-05: Double delete via shared_ptr cycle
 *
 * Creating a reference cycle with shared_ptr that causes
 * both objects to leak.
 *
 * Expected: memory_leak (CWE-401)
 * ================================================================ */
struct Node {
    std::shared_ptr<Node> next;
    int data;

    Node(int d) : data(d), next(nullptr) {}
    ~Node() { printf("Node(%d) destroyed\n", data); }
};

void cpp_bug_05_shared_ptr_cycle() {
    auto a = std::make_shared<Node>(1);
    auto b = std::make_shared<Node>(2);

    // Create cycle: a -> b -> a
    a->next = b;
    b->next = a;

    // [BUG] Reference cycle: both refcounts = 2
    // When a and b go out of scope, refcounts drop to 1, not 0
    // Both objects leak
}

/* ================================================================
 * CPP-BUG-06: FFI callback throws, stack unwinding misses cleanup
 *
 * C callback invokes C++ code that throws. The C stack frame
 * doesn't have exception handling, so the throw is unhandled.
 *
 * Expected: resource_leak / undefined_behavior
 * ================================================================ */
void cpp_callback(void* ctx, int value) {
    char* buf = (char*)ctx;

    if (value < 0) {
        // [BUG] Throwing through C callback boundary
        throw std::runtime_error("negative value in C callback");
    }

    printf("CPP-BUG-06 callback: %s, value=%d\n", buf, value);
}

void cpp_bug_06_exception_in_callback() {
    char* buf = new char[64];
    strcpy(buf, "callback context");

    c_ffi_register_callback(cpp_callback, buf);
    c_ffi_trigger_callback();  // May throw through C boundary

    delete[] buf;
}

/* ================================================================
 * CPP-BUG-07: Placement new without matching destructor call
 *
 * Using placement new but forgetting to call destructor
 * before freeing the memory.
 *
 * Expected: memory_leak (CWE-401)
 * ================================================================ */
void cpp_bug_07_placement_new_leak() {
    void* raw = c_ffi_alloc(sizeof(Derived));

    // Placement new — construct in C-allocated memory
    Derived* obj = new(raw) Derived();

    // [BUG] Forgot obj->~Derived() before free
    // Derived's destructor never runs, derived_data leaks
    c_ffi_free(raw);
}

/* ================================================================
 * CPP-BUG-08: Exception during construction leaks members
 *
 * Constructor throws after some members are allocated.
 * Members already constructed are properly destroyed, but
 * raw pointers allocated in the constructor body are not.
 *
 * Expected: memory_leak (CWE-401)
 * ================================================================ */
struct LeakyConstructor {
    char* buffer1;
    char* buffer2;

    LeakyConstructor() {
        buffer1 = new char[128];
        // Simulate: second allocation fails
        throw std::bad_alloc();
        buffer2 = new char[128];  // Never reached
    }

    ~LeakyConstructor() {
        delete[] buffer1;
        delete[] buffer2;
    }
};

void cpp_bug_08_constructor_throw() {
    try {
        LeakyConstructor obj;  // Throws during construction
    } catch (const std::bad_alloc&) {
        // [BUG] obj never fully constructed, destructor never called
        // buffer1 leaked
        printf("CPP-BUG-08: caught bad_alloc, but buffer1 leaked\n");
    }
}

/* ================================================================
 * Entry point
 * ================================================================ */
int main() {
    cpp_bug_01_new_array_delete_mismatch();
    cpp_bug_02_throw_through_c();
    cpp_bug_03_wrong_deleter();
    cpp_bug_04_missing_virtual_destructor();
    cpp_bug_05_shared_ptr_cycle();
    cpp_bug_06_exception_in_callback();
    cpp_bug_07_placement_new_leak();
    cpp_bug_08_constructor_throw();
    return 0;
}
