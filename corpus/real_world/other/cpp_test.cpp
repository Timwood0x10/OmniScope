/// C++ test file for OmniScope - exercises new/delete, smart pointers, STL containers
#include <memory>
#include <string>
#include <vector>
#include <map>
#include <cstring>

// Test function 1: raw new/delete
void test_raw_pointer() {
    int* data = new int[100];
    for (int i = 0; i < 100; i++) {
        data[i] = i * i;
    }
    int sum = 0;
    for (int i = 0; i < 100; i++) {
        sum += data[i];
    }
    delete[] data;
}

// Test function 2: unique_ptr (should be safe - automatic cleanup)
void test_unique_ptr() {
    auto ptr = std::make_unique<std::string>("hello world");
    auto len = ptr->length();
    (void)len;
}

// Test function 3: shared_ptr
void test_shared_ptr() {
    auto sptr = std::make_shared<std::vector<int>>(100, 42);
    auto sptr2 = sptr;
    (void)sptr2;
}

// Test function 4: potential leak path (conditional)
void* conditional_alloc(int flag) {
    void* buf = nullptr;
    if (flag > 0) {
        buf = new char[256];
        if (flag > 10) {
            return buf;
        }
        delete[] static_cast<char*>(buf);
    }
    return nullptr;
}

// Test function 5: map with heap-allocated values
void test_map_allocation() {
    std::map<std::string, std::unique_ptr<int>> m;
    m["key1"] = std::make_unique<int>(42);
    m["key2"] = std::make_unique<int>(100);
}

// Test function 6: vector growth (realloc pattern)
void test_vector_growth() {
    std::vector<std::string> vec;
    for (int i = 0; i < 50; i++) {
        vec.push_back("item_" + std::to_string(i));
    }
}

// Main entry point
int main() {
    test_raw_pointer();
    test_unique_ptr();
    test_shared_ptr();

    void* leaked = conditional_alloc(15);

    test_map_allocation();
    test_vector_growth();

    delete[] static_cast<char*>(leaked);
    return 0;
}
