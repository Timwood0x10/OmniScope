// Blockchain Transaction Hash Verifier Library
//
// Simulates a high-performance C crypto library used by blockchain nodes.
// Rust validators call this via FFI to verify transaction hashes.
//
// VULNERABILITY: Command injection in hash_lookup function
// Attack: Attacker can inject shell commands through hash string

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define HASH_TABLE_SIZE 256

typedef struct {
    char tx_hash[65];      // Transaction hash (64 chars + null)
    char sender[33];       // Sender address
    char receiver[33];     // Receiver address
    int amount;            // Amount transferred
    int verified;          // Verification status
} Transaction;

Transaction tx_table[HASH_TABLE_SIZE];
int tx_count = 0;

// Initialize the library
int crypto_init(void) {
    printf("[C] Crypto library initialized\n");
    memset(tx_table, 0, sizeof(tx_table));
    tx_count = 0;
    return 0;
}

// Register a transaction in the hash table
int register_transaction(const char* tx_hash, const char* sender, 
                         const char* receiver, int amount) {
    if (tx_count >= HASH_TABLE_SIZE) {
        return -1;
    }
    
    strncpy(tx_table[tx_count].tx_hash, tx_hash, 64);
    tx_table[tx_count].tx_hash[64] = '\0';
    strncpy(tx_table[tx_count].sender, sender, 32);
    tx_table[tx_count].sender[32] = '\0';
    strncpy(tx_table[tx_count].receiver, receiver, 32);
    tx_table[tx_count].receiver[32] = '\0';
    tx_table[tx_count].amount = amount;
    tx_table[tx_count].verified = 0;
    
    tx_count++;
    return 0;
}

// Look up a transaction by hash and verify it
// VULNERABILITY: Command injection via hash parameter
int verify_transaction(const char* tx_hash) {
    printf("[C] Looking up transaction: %s\n", tx_hash);
    
    // VULNERABILITY: hash is not sanitized before being used in system()
    // Attacker can inject: "; malicious_command; "
    char lookup_cmd[256];
    snprintf(lookup_cmd, sizeof(lookup_cmd), 
             "echo 'Looking up hash: %s' && grep -r '%s' /tmp/tx_db/ 2>/dev/null || echo 'Not found'",
             tx_hash, tx_hash);
    
    printf("[C] Executing: %s\n", lookup_cmd);
    int result = system(lookup_cmd);  // COMMAND INJECTION!
    
    // Find in local table
    for (int i = 0; i < tx_count; i++) {
        if (strncmp(tx_table[i].tx_hash, tx_hash, 64) == 0) {
            tx_table[i].verified = 1;
            return 0;
        }
    }
    
    return -1;
}

// Debug function: dump transaction info
// VULNERABILITY: Format string - tx_hash is used as format string
int debug_dump_transaction(const char* tx_hash) {
    printf("[C] Debug dump for: ");
    // VULNERABILITY: tx_hash should be %s but is directly used as format!
    printf(tx_hash);  // FORMAT STRING VULNERABILITY
    printf("\n");
    
    for (int i = 0; i < tx_count; i++) {
        if (strncmp(tx_table[i].tx_hash, tx_hash, 64) == 0) {
            printf("  Sender: %s\n", tx_table[i].sender);
            printf("  Receiver: %s\n", tx_table[i].receiver);
            printf("  Amount: %d\n", tx_table[i].amount);
            return 0;
        }
    }
    return -1;
}

// Process batch verification
// VULNERABILITY: Buffer overflow if count exceeds MAX_BATCH
int batch_verify(const char** hashes, int count) {
    printf("[C] Batch verifying %d transactions\n", count);
    
    int verified = 0;
    for (int i = 0; i < count; i++) {
        if (verify_transaction(hashes[i]) == 0) {
            verified++;
        }
    }
    
    return verified;
}

// Cleanup
void crypto_cleanup(void) {
    printf("[C] Cleaning up crypto library\n");
    memset(tx_table, 0, sizeof(tx_table));
    tx_count = 0;
}