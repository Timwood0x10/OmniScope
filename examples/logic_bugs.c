// Logical bug example - NTT butterfly operation bug
// This code compiles and runs without crashes, but produces WRONG results
// LLVM won't catch this - it's a mathematical/logical error

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#define MOD 998244353
#define MAX_SIZE 4096

// BUG: This is a LOGIC BUG, not a memory bug
// The butterfly operation has the wrong sign/operation
// Should be: (a + b) % MOD and (a - b + MOD) % MOD
// But implementation uses (a * b) % MOD which is COMPLETELY WRONG

void butterfly_wrong(uint32_t* a, uint32_t* b, uint32_t w) {
    // BUG: Multiplication instead of addition/subtraction!
    *a = ((uint64_t)*a * w) % MOD;
    *b = ((uint64_t)*b * w) % MOD;
    // Correct would be:
    // uint32_t temp = *a;
    // *a = (*a + *b) % MOD;
    // *b = (temp - *b + MOD) % MOD;
}

void butterfly_correct(uint32_t* a, uint32_t* b, uint32_t w) {
    uint32_t temp = *a;
    *a = ((uint64_t)*a + *b) % MOD;
    *b = ((uint64_t)temp - *b + MOD) % MOD;
    (void)w; // w not used in simple butterfly
}

// Forward FFT with wrong butterfly
void fft_wrong(uint32_t* data, size_t size) {
    for (size_t len = 2; len <= size; len *= 2) {
        for (size_t i = 0; i < size; i += len) {
            for (size_t j = 0; j < len / 2; j++) {
                butterfly_wrong(&data[i + j], &data[i + j + len / 2], j + 1);
            }
        }
    }
}

// Forward FFT with correct butterfly
void fft_correct(uint32_t* data, size_t size) {
    for (size_t len = 2; len <= size; len *= 2) {
        for (size_t i = 0; i < size; i += len) {
            for (size_t j = 0; j < len / 2; j++) {
                butterfly_correct(&data[i + j], &data[i + j + len / 2], j + 1);
            }
        }
    }
}

// Integer overflow bug in coefficient multiplication
// BUG: Not using modular multiplication - causes overflow for large values
uint32_t multiply_wrong(uint32_t a, uint32_t b) {
    return a * b; // BUG: Should be (uint64_t)a * b % MOD
}

uint32_t multiply_correct(uint32_t a, uint32_t b) {
    return (uint64_t)a * b % MOD;
}

// Conditional logic bug - wrong comparison
// BUG: Should be >= but code uses <=
// This can cause buffer underflow!
void process_with_bounds_wrong(int* data, size_t size, size_t index) {
    if (index <= size) {  // BUG: Should be index < size
        data[index] = 0;  // Can write to data[size] when index == size!
    }
}

void process_with_bounds_correct(int* data, size_t size, size_t index) {
    if (index < size) {
        data[index] = 0;
    }
}

// Off-by-one in loop termination
// BUG: Should be i < n but code uses i <= n
int sum_array_wrong(const int* arr, size_t n) {
    int sum = 0;
    for (size_t i = 0; i <= n; i++) {  // BUG: off-by-one!
        sum += arr[i];
    }
    return sum;
}

int sum_array_correct(const int* arr, size_t n) {
    int sum = 0;
    for (size_t i = 0; i < n; i++) {
        sum += arr[i];
    }
    return sum;
}

// Cryptographic bug: weak PRNG seed
// BUG: Using predictable seed (current time) instead of secure random
void init_prng_wrong(unsigned int* state) {
    *state = (unsigned int)time(NULL);  // BUG: Predictable!
}

// Correct secure initialization
void init_prng_correct(unsigned int* state) {
    // BUG: Still not truly secure, but better than time()
    FILE* f = fopen("/dev/urandom", "rb");
    if (f) {
        fread(state, sizeof(unsigned int), 1, f);
        fclose(f);
    } else {
        *state = (unsigned int)time(NULL) ^ (unsigned int)clock();
    }
}

// Logic error in coefficient comparison
// BUG: Should check magnitude but code checks raw values
int compare_coefficients_wrong(uint32_t a, uint32_t b) {
    // BUG: This comparison is WRONG for modular arithmetic
    // Example: a=MOD-1 (very negative), b=1 (very positive)
    // But MOD-1 > 1 in this comparison!
    if (a > b) return 1;
    if (a < b) return -1;
    return 0;
}

// Data flow from external source to comparison
// This is a SECURITY bug, not just logic bug
int process_user_threshold(const char* user_input) {
    int threshold = atoi(user_input);  // BUG: No validation
    // Threshold could be negative, causing issues downstream
    if (threshold < 0) {
        threshold = 0;  // BUG: This check is AFTER atoi, but too late!
    }
    return threshold;
}

// Entry point
int main(int argc, char* argv[]) {
    if (argc < 2) {
        printf("Usage: %s <command>\n", argv[0]);
        return 1;
    }

    if (strcmp(argv[1], "fft") == 0) {
        uint32_t data[8] = {1, 2, 3, 4, 5, 6, 7, 8};
        fft_wrong(data, 8);
        printf("FFT (wrong) complete\n");
    }
    else if (strcmp(argv[1], "mult") == 0) {
        uint32_t result = multiply_wrong(100000, 100000);
        printf("multiply_wrong: %u (likely overflowed)\n", result);
    }
    else if (strcmp(argv[1], "sum") == 0) {
        int arr[5] = {1, 2, 3, 4, 5};
        int s = sum_array_wrong(arr, 5);
        printf("sum_array_wrong: %d (includes garbage!)\n", s);
    }
    else if (strcmp(argv[1], "prng") == 0) {
        unsigned int state = 0;
        init_prng_wrong(&state);
        printf("PRNG seed: %u (predictable!)\n", state);
    }

    return 0;
}