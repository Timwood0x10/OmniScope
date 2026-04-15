// Real-world Distributed Computing System (C Layer)
//
// This C layer handles result aggregation, hash verification,
// and command execution for the distributed computing system.
//
// VULNERABILITIES:
// 1. c_aggregate_results() - Buffer overflow in result aggregation
// 2. c_verify_hash() - Buffer overflow in hash verification
// 3. c_execute_command() - Command injection via command parameter

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

// Aggregate results from compute nodes
// VULNERABILITY: Buffer overflow in output buffer
int c_aggregate_results(
    const char* node_id,
    const char* result_data,
    char* aggregated_output,
    int output_size
) {
    printf("[C] c_aggregate_results() called\n");
    printf("[C] Node ID: %s\n", node_id);
    printf("[C] Result data: %s\n", result_data);

    // VULNERABILITY: No bounds checking on result_data length!
    // If result_data is very long, this will overflow aggregated_output buffer
    strcpy(aggregated_output, "node=");
    strcat(aggregated_output, node_id);
    strcat(aggregated_output, ";data=");
    strcat(aggregated_output, result_data);  // Buffer overflow!

    printf("[C] Aggregated: %s\n", aggregated_output);
    printf("[C] WARNING: Output buffer may overflow!\n");

    return 0;
}

// Verify hash of aggregated data
// VULNERABILITY: Buffer overflow in verification result
int c_verify_hash(
    const char* data,
    const char* expected_hash,
    char* verification_result,
    int result_size
) {
    printf("[C] c_verify_hash() called\n");
    printf("[C] Data length: %zu\n", strlen(data));
    printf("[C] Expected hash: %s\n", expected_hash);

    // Simulate hash verification (in real system, would use crypto library)
    unsigned int hash = 0;
    for (size_t i = 0; i < strlen(data); i++) {
        hash = hash * 31 + data[i];
    }

    // Convert hash to string
    char actual_hash[32];
    snprintf(actual_hash, sizeof(actual_hash), "%08x", hash);

    // Compare hashes
    if (strcmp(actual_hash, expected_hash) == 0) {
        // VULNERABILITY: No bounds checking on verification_result!
        strcpy(verification_result, "VERIFIED");  // Should be safe, but pattern is risky
    } else {
        strcpy(verification_result, "FAILED");
    }

    printf("[C] Actual hash: %s\n", actual_hash);
    printf("[C] Verification: %s\n", verification_result);

    return 0;
}

// Execute command based on verification
// VULNERABILITY: Command injection via command parameter
int c_execute_command(
    const char* command,
    const char* verification_token
) {
    printf("[C] c_execute_command() called\n");
    printf("[C] Command: %s\n", command);
    printf("[C] Verification token: %s\n", verification_token);

    // Build shell command
    char shell_command[512];

    // VULNERABILITY: Command parameter is not sanitized!
    // If command contains shell metacharacters, command injection occurs
    snprintf(shell_command, sizeof(shell_command),
             "/usr/bin/compute_executor --command %s --token %s 2>/dev/null",
             command, verification_token);

    printf("[C] Executing: %s\n", shell_command);

    // Execute command - COMMAND INJECTION!
    int result = system(shell_command);

    printf("[C] Command completed with status: %d\n", result);
    return result;
}