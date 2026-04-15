// A sample C program with potential issues for analysis
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// Potential buffer overflow
void process_data(char* input) {
    char buffer[64];
    strcpy(buffer, input);  // Potential overflow if input > 64 chars
    printf("Data: %s\n", buffer);
}

// Memory leak
int* allocate_array(int size) {
    int* arr = malloc(size * sizeof(int));
    // Missing: free(arr) before return
    return arr;
}

// Use after free (simplified)
char* get_name() {
    char* name = malloc(32);
    strcpy(name, "Test");
    free(name);
    return name;  // Dangling pointer
}

// Null pointer dereference
int handle_null(int* ptr) {
    return ptr[0];  // Crash if ptr is NULL
}

// Double free (simplified)
void free_twice(char* data) {
    free(data);
    free(data);  // Double free
}

int main(int argc, char* argv[]) {
    if (argc < 2) {
        printf("Usage: %s <input>\n", argv[0]);
        return 1;
    }

    process_data(argv[1]);

    int* arr = allocate_array(100);
    for (int i = 0; i < 100; i++) {
        arr[i] = i;
    }
    free(arr);  // This frees the memory, but the function already returned without freeing

    char* name = get_name();
    printf("Name: %s\n", name);  // Use after free

    handle_null(NULL);  // Will crash

    return 0;
}
