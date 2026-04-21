// OpenSSL FFI Wrapper Example
// Demonstrates common OpenSSL API usage patterns with intentional bugs
//
// NOTE: This file uses mock declarations instead of actual OpenSSL headers
// to ensure portability. The patterns are realistic and represent common bugs.
//
// Expected issues:
// 1. EVP_CIPHER_CTX without EVP_CIPHER_CTX_free (leak)
// 2. BIO without BIO_free (leak)
// 3. RSA without RSA_free (leak)
// 4. Unchecked return values on critical functions
// 5. Weak key generation
// 6. Sensitive data not zeroized

#include <stdlib.h>
#include <string.h>
#include <stdio.h>

// Mock OpenSSL types
typedef struct EVP_CIPHER_CTX EVP_CIPHER_CTX;
typedef struct BIO BIO;
typedef struct RSA RSA;
typedef struct BIGNUM BIGNUM;
typedef struct EVP_PKEY EVP_PKEY;
typedef struct EVP_PKEY_CTX EVP_PKEY_CTX;
typedef struct SSL_CTX SSL_CTX;
typedef struct X509 X509;

// Mock constants
#define EVP_PKEY_RSA 1
#define Z_OK 0
#define Z_STREAM_END 1

// Mock OpenSSL functions (declarations only for IR generation)
extern EVP_CIPHER_CTX* EVP_CIPHER_CTX_new(void);
extern void EVP_CIPHER_CTX_free(EVP_CIPHER_CTX* ctx);
extern int EVP_EncryptInit_ex(EVP_CIPHER_CTX* ctx, void* type, 
                               void* impl, const unsigned char* key, 
                               const unsigned char* iv);
extern int EVP_EncryptUpdate(EVP_CIPHER_CTX* ctx, unsigned char* out,
                              int* outl, const unsigned char* in, int inl);
extern int EVP_EncryptFinal_ex(EVP_CIPHER_CTX* ctx, unsigned char* out, int* outl);
extern void* EVP_aes_128_cbc(void);
extern void* EVP_aes_256_cbc(void);

extern BIO* BIO_new(void* type);
extern BIO* BIO_new_file(const char* filename, const char* mode);
extern BIO* BIO_new_mem_buf(void* buf, int len);
extern void* BIO_s_mem(void);
extern int BIO_write(BIO* b, const void* buf, int len);
extern int BIO_read(BIO* b, void* buf, int len);
extern void BIO_free(BIO* a);

extern RSA* RSA_new(void);
extern void RSA_free(RSA* r);
extern int RSA_generate_key_ex(RSA* rsa, int bits, BIGNUM* e, void* cb);
#define RSA_F4 65537

extern BIGNUM* BN_new(void);
extern void BN_free(BIGNUM* a);
extern int BN_set_word(BIGNUM* a, unsigned long w);

extern EVP_PKEY* EVP_PKEY_new(void);
extern void EVP_PKEY_free(EVP_PKEY* key);
extern EVP_PKEY_CTX* EVP_PKEY_CTX_new_id(int id, void* e);
extern void EVP_PKEY_CTX_free(EVP_PKEY_CTX* ctx);
extern int EVP_PKEY_keygen_init(EVP_PKEY_CTX* ctx);
extern int EVP_PKEY_CTX_set_rsa_keygen_bits(EVP_PKEY_CTX* ctx, int bits);
extern int EVP_PKEY_keygen(EVP_PKEY_CTX* ctx, EVP_PKEY** ppkey);

extern SSL_CTX* SSL_CTX_new(void* method);
extern void SSL_CTX_free(SSL_CTX* ctx);
extern void* TLS_method(void);
extern int SSL_VERIFY_PEER;

extern X509* X509_new(void);
extern void X509_free(X509* a);
extern X509* PEM_read_bio_X509(BIO* bp, void* x, void* cb, void* u);

extern void OpenSSL_add_all_algorithms(void);
extern void SSL_load_error_strings(void);
extern void EVP_cleanup(void);
extern void ERR_free_strings(void);
extern void ERR_print_errors_fp(FILE* fp);
extern void sqlite3_free(void* ptr);

extern int RAND_bytes(unsigned char* buf, int num);
extern void RAND_seed(const void* buf, int num);

extern void OPENSSL_cleanse(void* ptr, size_t len);

// Bug 1: EVP_CIPHER_CTX leak
int encrypt_leak_ctx(const unsigned char* plaintext, int len) {
    EVP_CIPHER_CTX* ctx = EVP_CIPHER_CTX_new();
    if (!ctx) return -1;
    
    // Missing: EVP_CIPHER_CTX_free(ctx);
    return 0;  // Leak: ctx never freed
}

// Bug 2: BIO chain leak
int bio_leak(const char* data) {
    BIO* bio = BIO_new(BIO_s_mem());
    BIO_write(bio, data, strlen(data));
    
    // Missing: BIO_free(bio);
    return 0;  // Leak: bio never freed
}

// Bug 3: RSA key leak
int rsa_key_leak() {
    RSA* rsa = RSA_new();
    BIGNUM* bn = BN_new();
    BN_set_word(bn, RSA_F4);
    
    RSA_generate_key_ex(rsa, 2048, bn, NULL);
    
    // Missing: RSA_free(rsa);
    BN_free(bn);
    return 0;  // Leak: rsa never freed
}

// Bug 4: Unchecked EVP_EncryptInit_ex return value
int encrypt_unchecked(unsigned char* ciphertext, const unsigned char* plaintext) {
    EVP_CIPHER_CTX* ctx = EVP_CIPHER_CTX_new();
    
    unsigned char key[16] = {0};
    unsigned char iv[16] = {0};
    
    // Bug: return value not checked
    EVP_EncryptInit_ex(ctx, EVP_aes_128_cbc(), NULL, key, iv);
    
    int len;
    EVP_EncryptUpdate(ctx, ciphertext, &len, plaintext, 16);
    
    EVP_CIPHER_CTX_free(ctx);
    return 0;
}

// Bug 5: Weak random number generation
int weak_random(unsigned char* buf, int len) {
    // Bug: Using predictable seed
    unsigned char seed[16] = {1, 2, 3, 4, 5, 6, 7, 8, 
                               9, 10, 11, 12, 13, 14, 15, 16};
    RAND_seed(seed, 16);
    
    RAND_bytes(buf, len);
    return 0;
}

// Bug 6: Sensitive data not zeroized
int password_handling(const char* password) {
    char pwd[64];
    strncpy(pwd, password, sizeof(pwd) - 1);
    pwd[sizeof(pwd) - 1] = '\0';
    
    // Use password for encryption...
    printf("Using password: %s\n", pwd);
    
    // Bug: password not zeroized before return
    // Missing: OPENSSL_cleanse(pwd, sizeof(pwd));
    return 0;
}

// Bug 7: SSL context without proper cleanup
int ssl_ctx_leak() {
    SSL_CTX* ctx = SSL_CTX_new(TLS_method());
    if (!ctx) return -1;
    
    // SSL_CTX_set_verify(ctx, SSL_VERIFY_PEER, NULL);
    
    // Missing: SSL_CTX_free(ctx);
    return 0;  // Leak
}

// Bug 8: X509 certificate leak
int x509_leak() {
    X509* cert = X509_new();
    if (!cert) return -1;
    
    // Set certificate properties...
    
    // Missing: X509_free(cert);
    return 0;  // Leak
}

// Bug 9: Private key in memory without protection
int unprotected_key() {
    EVP_PKEY* pkey = NULL;
    EVP_PKEY_CTX* ctx = EVP_PKEY_CTX_new_id(EVP_PKEY_RSA, NULL);
    
    EVP_PKEY_keygen_init(ctx);
    EVP_PKEY_CTX_set_rsa_keygen_bits(ctx, 2048);
    EVP_PKEY_keygen(ctx, &pkey);
    
    // Bug: Private key left in memory without encryption
    
    EVP_PKEY_CTX_free(ctx);
    EVP_PKEY_free(pkey);
    return 0;
}

// Bug 10: Error handling without proper cleanup
int error_handling_bug(const char* cert_path) {
    BIO* bio = BIO_new_file(cert_path, "r");
    if (!bio) {
        // Bug: ERR_print_errors_fp writes to stderr but we don't handle the error
        ERR_print_errors_fp(stderr);
        return -1;
    }
    
    X509* cert = PEM_read_bio_X509(bio, NULL, NULL, NULL);
    if (!cert) {
        // Bug: bio not freed on error path
        ERR_print_errors_fp(stderr);
        return -1;  // Leak: bio
    }
    
    BIO_free(bio);
    X509_free(cert);
    return 0;
}

// Correct pattern for reference
int correct_encryption(const unsigned char* plaintext, int len,
                       unsigned char* ciphertext, const unsigned char* key) {
    EVP_CIPHER_CTX* ctx = EVP_CIPHER_CTX_new();
    if (!ctx) return -1;
    
    unsigned char iv[16];
    if (RAND_bytes(iv, 16) != 1) {
        EVP_CIPHER_CTX_free(ctx);
        return -1;
    }
    
    if (EVP_EncryptInit_ex(ctx, EVP_aes_256_cbc(), NULL, key, iv) != 1) {
        EVP_CIPHER_CTX_free(ctx);
        return -1;
    }
    
    int out_len;
    if (EVP_EncryptUpdate(ctx, ciphertext, &out_len, plaintext, len) != 1) {
        EVP_CIPHER_CTX_free(ctx);
        return -1;
    }
    
    int final_len;
    if (EVP_EncryptFinal_ex(ctx, ciphertext + out_len, &final_len) != 1) {
        EVP_CIPHER_CTX_free(ctx);
        return -1;
    }
    
    EVP_CIPHER_CTX_free(ctx);
    return out_len + final_len;
}

int main() {
    OpenSSL_add_all_algorithms();
    SSL_load_error_strings();
    
    // Run buggy functions
    encrypt_leak_ctx((unsigned char*)"test", 4);
    bio_leak("test data");
    rsa_key_leak();
    encrypt_unchecked(NULL, (unsigned char*)"test");
    
    unsigned char buf[16];
    weak_random(buf, 16);
    password_handling("secret_password");
    
    EVP_cleanup();
    ERR_free_strings();
    return 0;
}
