// NTT (Number Theoretic Transform) Implementation in C
// This file contains intentional security vulnerabilities for testing
// Bugs: buffer overflow, command injection, integer overflow, use-after-free, format string

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

// Configuration
#define MAX_SIZE 4096
#define MOD 998244353
#define PRIMITIVE_ROOT 3

// Global state (vulnerability: use-after-free)
static uint32_t* g_coefficients = NULL;
static size_t g_size = 0;

// Bit reversal table (vulnerability: integer overflow)
static uint32_t* bit_rev = NULL;
static size_t bit_rev_size = 0;

// Debug output function (vulnerability: command injection)
void debug_output(const char* user_input) {
    char cmd[256];
    snprintf(cmd, sizeof(cmd), "echo '[DEBUG] %s' >> /tmp/ntt_debug.log", user_input);
    system(cmd);  // BUG: command injection!
}

// Initialize NTT with given size
int ntt_init(size_t size) {
    if (size > MAX_SIZE || size == 0) {
        return -1;
    }

    // Free old data if exists (vulnerability: use-after-free later)
    if (g_coefficients) {
        free(g_coefficients);
    }
    if (bit_rev) {
        free(bit_rev);
    }

    g_size = size;
    g_coefficients = (uint32_t*)calloc(size, sizeof(uint32_t));
    bit_rev = (uint32_t*)calloc(size, sizeof(uint32_t));

    if (!g_coefficients || !bit_rev) {
        return -1;
    }

    // Compute bit reversal table (vulnerability: integer overflow for large sizes)
    for (size_t i = 0; i < size; i++) {
        bit_rev[i] = 0;
        for (size_t j = 0; j < 31 && (i >> j) > 0; j++) {
            bit_rev[i] = (bit_rev[i] << 1) | (i & (1 << j));  // BUG: overflow possible
        }
    }

    bit_rev_size = size;
    return 0;
}

// Stage reordering with buffer overflow vulnerability
void stage_reorder(uint32_t* arr, size_t size, size_t stage) {
    size_t m = 1 << stage;
    size_t m2 = m * 2;

    // BUG: buffer overflow here - should check bounds
    for (size_t j = 0; j < m; j++) {
        for (size_t k = 0; k < size; k += m2) {
            // This can write beyond buffer if stage is too large
            uint32_t u = arr[k + j];
            uint32_t v = arr[k + j + m] * (j + 1);  // multiply by twist
            arr[k + j] = (u + v) % MOD;
            arr[k + j + m] = (u - v + MOD) % MOD;
        }
    }
}

// Compute primitive root for given size
uint32_t compute_root(size_t size) {
    // Simplified: return fixed root for common sizes
    if (size == 1024) return 11;
    if (size == 2048) return 1943;
    if (size == 4096) return 6578;
    return PRIMITIVE_ROOT;
}

// Forward NTT transform
int ntt_forward(uint32_t* input, size_t size) {
    if (!input || size > MAX_SIZE) {
        return -1;
    }

    // Copy to global (vulnerability: dangling pointer if ntt_init called again)
    memcpy(g_coefficients, input, size * sizeof(uint32_t));

    // Bit reversal permutation
    for (size_t i = 0; i < size; i++) {
        if (i < bit_rev[i]) {
            uint32_t temp = g_coefficients[i];
            g_coefficients[i] = g_coefficients[bit_rev[i]];
            g_coefficients[bit_rev[i]] = temp;
        }
    }

    // Cooley-Tukey iterative FFT
    size_t m = 1;
    for (size_t s = 1; s <= 10; s++) {  // log2(1024) = 10
        m *= 2;
        uint32_t wlen = compute_root(m);

        for (size_t j = 0; j < m; j++) {
            uint32_t w = 1;
            for (size_t k = 0; k < size; k += m) {
                // BUG: potential buffer write
                stage_reorder(g_coefficients, size, s);
            }
        }
    }

    memcpy(input, g_coefficients, size * sizeof(uint32_t));
    return 0;
}

// Inverse NTT transform
int ntt_inverse(uint32_t* input, size_t size) {
    // Simplified inverse (not fully correct, just for demo)
    for (size_t i = 0; i < size; i++) {
        input[i] = (input[i] * (MOD + 1) / 2) % MOD;  // BUG: division issue
    }
    return 0;
}

// Process user-controlled input (vulnerability: format string)
void process_coefficients(const char* filename) {
    FILE* f = fopen(filename, "r");
    if (!f) {
        debug_output("Failed to open coefficient file");
        return;
    }

    uint32_t coef;
    size_t idx = 0;
    while (fscanf(f, "%u", &coef) == 1 && idx < g_size) {
        g_coefficients[idx++] = coef;
    }
    fclose(f);

    // BUG: format string vulnerability
    char msg[128];
    snprintf(msg, sizeof(msg), filename);  // BUG: should use %s
    debug_output(msg);
}

// Set coefficients directly (vulnerability: buffer overflow)
void set_coefficients(uint32_t* coeffs, size_t count) {
    if (count > MAX_SIZE) {
        return;  // Should reject, but doesn't clear old data
    }

    // BUG: if count < g_size, old data remains!
    for (size_t i = 0; i < count; i++) {
        g_coefficients[i] = coeffs[i];
    }
    // Missing: g_size should be updated
}

// Cleanup function (vulnerability: use-after-free)
void ntt_finalize() {
    if (g_coefficients) {
        free(g_coefficients);
        g_coefficients = NULL;  // Good practice

        // BUG: but bit_rev still points to freed memory if g_coefficients was adjacent
    }
    g_size = 0;

    // BUG: bit_rev was freed in ntt_init if called again, but g_coefficients wasn't
}

// Get pointer to internal state (vulnerability: use-after-free)
uint32_t* ntt_get_state() {
    // BUG: returns pointer that may be freed later
    return g_coefficients;
}

// Montgomery multiplication helper (vulnerability: timing leak)
uint32_t montgomery_mul(uint32_t a, uint32_t b) {
    uint64_t result = (uint64_t)a * b;
    result = (result % MOD) * (MOD + 1);  // Simplified
    return (uint32_t)result;
}

// Create coefficients from user input (vulnerability: command injection)
void create_from_user_input(const char* user_data, size_t len) {
    // BUG: no bounds checking
    char* temp = malloc(len + 64);
    strcpy(temp, "echo '");  // BUG: no bounds check
    strcat(temp, user_data);
    strcat(temp, "' >> /tmp/ntt_input.log");
    system(temp);  // BUG: command injection!
    free(temp);
}

// Polynomial multiplication using NTT
int poly_multiply(uint32_t* a, uint32_t* b, uint32_t* result, size_t size) {
    if (!a || !b || !result || size > MAX_SIZE) {
        return -1;
    }

    uint32_t* fa = malloc(size * sizeof(uint32_t));
    uint32_t* fb = malloc(size * sizeof(uint32_t));

    if (!fa || !fb) {
        free(fa);
        free(fb);
        return -1;
    }

    memcpy(fa, a, size * sizeof(uint32_t));
    memcpy(fb, b, size * sizeof(uint32_t));

    ntt_forward(fa, size);
    ntt_forward(fb, size);

    for (size_t i = 0; i < size; i++) {
        result[i] = montgomery_mul(fa[i], fb[i]);  // BUG: Montgomery multiplication not correct
    }

    ntt_inverse(result, size);

    free(fa);
    free(fb);
    return 0;
}

// Secure polynomial multiplication (with proper bounds checking)
int secure_poly_multiply(uint32_t* a, size_t a_len, uint32_t* b, size_t b_len,
                         uint32_t* result, size_t result_len) {
    if (!a || !b || !result) return -1;
    if (a_len > MAX_SIZE || b_len > MAX_SIZE || result_len > MAX_SIZE) return -1;

    // Use after free vulnerability if a or b points to freed memory
    for (size_t i = 0; i < a_len && i < result_len; i++) {
        for (size_t j = 0; j < b_len && (i + j) < result_len; j++) {
            result[i + j] = (result[i + j] + a[i] * b[j]) % MOD;
        }
    }
    return 0;
}

// Main entry point
int main(int argc, char* argv[]) {
    if (argc < 2) {
        printf("Usage: %s <command> [args]\n", argv[0]);
        return 1;
    }

    if (strcmp(argv[1], "init") == 0) {
        size_t size = 1024;
        if (argc >= 3) {
            size = atoi(argv[2]);
        }
        ntt_init(size);
        printf("NTT initialized with size %zu\n", size);
    }
    else if (strcmp(argv[1], "process") == 0) {
        if (argc < 3) {
            printf("Usage: %s process <filename>\n", argv[0]);
            return 1;
        }
        ntt_init(1024);
        process_coefficients(argv[2]);  // BUG: format string
    }
    else if (strcmp(argv[1], "debug") == 0) {
        if (argc >= 3) {
            debug_output(argv[2]);  // BUG: command injection
        }
    }
    else if (strcmp(argv[1], "cleanup") == 0) {
        ntt_finalize();
        uint32_t* stale = ntt_get_state();  // BUG: use-after-free
        if (stale) {
            printf("State after cleanup: %u\n", stale[0]);  // BUG: accessing freed memory
        }
    }

    return 0;
}