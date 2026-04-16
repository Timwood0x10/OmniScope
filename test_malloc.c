#include <stdio.h>
#include <stdlib.h>

void test_unchecked_malloc() {
    void* ptr = malloc(1024);
    // BUG: No null check after malloc
    printf("Allocated: %p\n", ptr);
}

void test_checked_malloc() {
    void* ptr = malloc(1024);
    if (ptr == NULL) {
        printf("Allocation failed\n");
        return;
    }
    printf("Allocated: %p\n", ptr);
}

void test_unchecked_open() {
    FILE* f = fopen("test.txt", "r");
    // BUG: No null check after fopen
    fprintf(f, "test\n");
}

void test_unchecked_system() {
    int result = system("ls");
    // BUG: Return value not checked for success/failure
}

int main() {
    test_unchecked_malloc();
    test_checked_malloc();
    test_unchecked_open();
    test_unchecked_system();
    return 0;
}