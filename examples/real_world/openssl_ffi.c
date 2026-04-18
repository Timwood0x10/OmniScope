// Real-world FFI Test: OpenSSL EVP API Patterns
// Simplified version without external headers for testing

#include <stdlib.h>
#include <string.h>
#include <stdio.h>

// Mock OpenSSL types for testing
typedef struct { char data[64]; } EVP_CIPHER_CTX;
typedef struct { char data[64]; } BIO;
typedef struct { char data[64]; } EVP_PKEY;
typedef struct { char data[64]; } SSL_CTX;

// Mock functions simulating OpenSSL API
EVP_CIPHER_CTX* EVP_CIPHER_CTX_new(void) { return malloc(sizeof(EVP_CIPHER_CTX)); }
void EVP_CIPHER_CTX_free(EVP_CIPHER_CTX *ctx) { free(ctx); }
BIO* BIO_new(void *type) { return malloc(sizeof(BIO)); }
BIO* BIO_new_file(const char *filename, const char *mode) { return malloc(sizeof(BIO)); }
void BIO_free(BIO *bio) { free(bio); }
EVP_PKEY* PEM_read_bio_PrivateKey(BIO *bp, void *x, void *cb, void *u) { return malloc(sizeof(EVP_PKEY)); }
void EVP_PKEY_free(EVP_PKEY *pkey) { free(pkey); }
SSL_CTX* SSL_CTX_new(void *method) { return malloc(sizeof(SSL_CTX)); }
void SSL_CTX_free(SSL_CTX *ctx) { free(ctx); }
void* TLS_server_method(void) { return NULL; }

// Issue: EVP_CIPHER_CTX_new requires EVP_CIPHER_CTX_free
EVP_CIPHER_CTX* create_cipher_context(void) {
    EVP_CIPHER_CTX *ctx = EVP_CIPHER_CTX_new();
    if (!ctx) {
        return NULL;
    }
    // Missing: EVP_CIPHER_CTX_free will be needed
    return ctx;
}

// Issue: Key buffer allocated but ownership unclear
int encrypt_data(const unsigned char *plaintext, int plaintext_len,
                 unsigned char *key, unsigned char *iv,
                 unsigned char *ciphertext) {
    EVP_CIPHER_CTX *ctx = EVP_CIPHER_CTX_new();
    if (!ctx) return -1;

    // Issue: ctx leaked on error path
    // Fix: Add EVP_CIPHER_CTX_free(ctx) before return -1 to prevent memory leak
    // Simulating: if (EVP_EncryptInit_ex(ctx, ...) != 1) return -1;
    int init_failed = 0;
    if (init_failed) {
        // Missing: EVP_CIPHER_CTX_free(ctx);
        return -1;
    }

    // Process...

    EVP_CIPHER_CTX_free(ctx);
    return 0;
}

// Issue: Double free potential
void process_with_cleanup(unsigned char *data, size_t len) {
    unsigned char *buffer = malloc(len);
    if (!buffer) return;

    memcpy(buffer, data, len);

    // Process buffer...

    free(buffer);

    // Issue: Potential double free if error path taken
    if (len > 1024) {
        free(buffer);  // Double free!
    }
}

// Issue: BIO_new with missing BIO_free
BIO* create_bio_buffer(void) {
    BIO *bio = BIO_new(NULL);
    if (!bio) return NULL;
    // Missing: BIO_free will be needed
    return bio;
}

// Issue: PEM_read_bio_PrivateKey with missing EVP_PKEY_free
EVP_PKEY* load_private_key(const char *filename) {
    BIO *bio = BIO_new_file(filename, "r");
    if (!bio) return NULL;

    EVP_PKEY *pkey = PEM_read_bio_PrivateKey(bio, NULL, NULL, NULL);
    // Issue: BIO not freed on error
    if (!pkey) {
        BIO_free(bio);
        return NULL;
    }

    BIO_free(bio);
    // Caller must EVP_PKEY_free(pkey)
    return pkey;
}

// Issue: SSL_CTX_new with missing SSL_CTX_free
SSL_CTX* create_ssl_context(void) {
    const void *method = TLS_server_method();
    SSL_CTX *ctx = SSL_CTX_new(method);
    if (!ctx) return NULL;
    // Missing: SSL_CTX_free will be needed
    return ctx;
}

// Issue: Resource leak in error path
int process_data_with_leak(const char *input, size_t len) {
    unsigned char *buffer1 = malloc(len);
    if (!buffer1) return -1;

    unsigned char *buffer2 = malloc(len * 2);
    if (!buffer2) {
        // Issue: buffer1 not freed
        return -1;
    }

    unsigned char *buffer3 = malloc(len * 3);
    if (!buffer3) {
        // Issue: buffer1 and buffer2 not freed
        free(buffer2);
        return -1;
    }

    // Process...

    free(buffer1);
    free(buffer2);
    free(buffer3);
    return 0;
}

// Issue: Use after free
int use_after_free_example(unsigned char *data, size_t len) {
    unsigned char *buffer = malloc(len);
    if (!buffer) return -1;

    memcpy(buffer, data, len);
    free(buffer);

    // Issue: Use after free
    if (len > 0) {
        buffer[0] = 0;  // Use after free!
    }

    return 0;
}

// Issue: Memory leak - allocated but never freed
unsigned char* allocate_without_free(size_t size) {
    unsigned char *data = malloc(size);
    if (!data) return NULL;

    // Initialize data...
    memset(data, 0, size);

    // Issue: Caller may forget to free
    return data;
}

// Correct pattern: proper cleanup
int correct_pattern_example(const char *input, size_t len) {
    unsigned char *buffer = malloc(len);
    if (!buffer) return -1;

    unsigned char *aux = malloc(len);
    if (!aux) {
        free(buffer);
        return -1;
    }

    // Process...

    free(buffer);
    free(aux);
    return 0;
}
