// Real-world Simple Distributed Computing (C++)
//
// Simplified version that directly calls C functions from main
// to ensure clear call graph for OmniScope analysis.

#include <iostream>
#include <string>

// C layer declarations
extern "C" {
    // Aggregate results from compute nodes
    int c_aggregate_results(
        const char* node_id,
        const char* result_data,
        char* aggregated_output,
        int output_size
    );

    // Verify hash of aggregated results
    int c_verify_hash(
        const char* data,
        const char* expected_hash,
        char* verification_result,
        int result_size
    );

    // Execute final command based on verification
    int c_execute_command(
        const char* command,
        const char* verification_token
    );
}

int main(int argc, char* argv[]) {
    std::cout << "=== Distributed Computing System (Simple) ===" << std::endl;

    // Scenario 1: Normal operation
    std::cout << "[Scenario 1] Normal operation:" << std::endl;
    char output1[1024];
    c_aggregate_results("node_01", "result_data_123", output1, sizeof(output1));

    char verify_result[512];
    c_verify_hash(output1, "a1b2c3d4", verify_result, sizeof(verify_result));

    c_execute_command("deploy", "token_12345");
    std::cout << std::endl;

    // Scenario 2: User-controlled input (VULNERABLE)
    std::cout << "[Scenario 2] User-controlled input:" << std::endl;
    std::string user_input = "user_command";  // User input - flows to C layer

    // Directly call C function with user input - VULNERABLE!
    c_execute_command(user_input.c_str(), "token_67890");

    std::cout << "\n[C++] WARNING: User input flows to C layer without validation!" << std::endl;

    return 0;
}