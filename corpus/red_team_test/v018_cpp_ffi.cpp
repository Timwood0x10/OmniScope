// OmniScope v0.1.8 — C++ FFI Red Team Test
// Intentional C++ cross-language FFI vulnerabilities
//
// Bugs: 8 | Controls: 2

#include <memory>
#include <cstdlib>
#include <cstring>
#include <vector>

extern "C" void c_free(void* p) { free(p); }
extern "C" void c_take_ptr(void* p) {}
extern "C" void c_register_callback(void (*cb)(void*), void* ctx) {}
extern "C" void* c_malloc(size_t n) { return malloc(n); }

// BUG-CPP-01: C++ unique_ptr released to C free — cross-lang free mismatch
void bug_cpp_01_unique_ptr_to_c_free() {
    auto p = std::make_unique<int>(42);
    c_free(p.release());  // C++ new → C free()
}

// BUG-CPP-02: C pointer stored in unique_ptr, freed by C++ delete
void bug_cpp_02_c_malloc_to_cpp_delete() {
    int* p = (int*)c_malloc(sizeof(int));
    std::unique_ptr<int> up(p);  // Will call delete on C malloc'd ptr
}

// BUG-CPP-03: Stack address passed to C FFI
void bug_cpp_03_stack_to_c() {
    int local = 42;
    c_take_ptr(&local);  // Stack address escapes to C
}

// BUG-CPP-04: Vector data pointer escapes to C
void bug_cpp_04_vector_data_to_c() {
    std::vector<int> v = {1, 2, 3};
    c_take_ptr(v.data());  // Heap data ptr escapes, lifetime unclear
}

// BUG-CPP-05: Unique_ptr raw pointer escapes to C callback
void bug_cpp_05_unique_ptr_callback_escape() {
    auto p = std::make_unique<int>(42);
    int* raw = p.get();
    c_register_callback([](void* ctx) {
        int* val = (int*)ctx;
        *val = 99;
    }, raw);  // Callback may fire after unique_ptr destroyed
}

// BUG-CPP-06: C-string from C returned without free
void bug_cpp_06_c_string_leak() {
    char* s = strdup("hello from C");
    c_take_ptr(s);
    // Never freed
}

// BUG-CPP-07: Virtual call after object destruction (UB after FFI)
struct Base {
    virtual void f() {}
    virtual ~Base() = default;
};
struct Derived : Base {
    void f() override {}
};

void bug_cpp_07_vtable_after_destroy() {
    auto* d = new Derived();
    delete d;
    d->f();  // Virtual call on destroyed object
}

// BUG-CPP-08: Double free via shared_ptr + raw ptr
void bug_cpp_08_shared_ptr_raw_double_free() {
    auto sp = std::make_shared<int>(42);
    int* raw = sp.get();
    c_free(raw);  // frees shared_ptr's managed memory
    // sp destructor will free again
}

// CONTROL-01: Correct unique_ptr + release + manual free
void control_01_correct_unique_ptr_release() {
    auto p = static_cast<int*>(c_malloc(sizeof(int)));
    *p = 42;
    c_free(p);
}

// CONTROL-02: Correct shared_ptr scope
void control_02_correct_shared_ptr() {
    auto sp = std::make_shared<int>(42);
    c_take_ptr(sp.get());
}

int main() {
    bug_cpp_01_unique_ptr_to_c_free();
    bug_cpp_02_c_malloc_to_cpp_delete();
    bug_cpp_03_stack_to_c();
    bug_cpp_04_vector_data_to_c();
    bug_cpp_05_unique_ptr_callback_escape();
    bug_cpp_06_c_string_leak();
    bug_cpp_07_vtable_after_destroy();
    bug_cpp_08_shared_ptr_raw_double_free();
    control_01_correct_unique_ptr_release();
    control_02_correct_shared_ptr();
    return 0;
}
