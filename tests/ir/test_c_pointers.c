// C test: Pointers and memory operations
#include <stdlib.h>

typedef struct {
    int* data;
    int size;
} IntArray;

IntArray* create_array(int size) {
    IntArray* arr = malloc(sizeof(IntArray));
    arr->data = malloc(sizeof(int) * size);
    arr->size = size;
    for (int i = 0; i < size; i++) {
        arr->data[i] = i * 2;
    }
    return arr;
}

int sum_array(IntArray* arr) {
    int sum = 0;
    for (int i = 0; i < arr->size; i++) {
        sum += arr->data[i];
    }
    return sum;
}

void free_array(IntArray* arr) {
    free(arr->data);
    free(arr);
}

int main() {
    IntArray* arr = create_array(10);
    int sum = sum_array(arr);
    free_array(arr);
    return sum;
}
