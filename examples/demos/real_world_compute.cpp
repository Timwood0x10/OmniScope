// Real-world Distributed Computing System (C++ Layer)
//
// SCENARIO: A distributed computing system where C++ handles
// business logic and data processing, while C handles result
// aggregation and verification.
//
// This is a REAL production scenario:
// - C++: Business logic, data processing, complex algorithms
// - C: System operations, result verification, command execution
// - Cross-language: Data flows from C++ → C for final verification

#include <iostream>
#include <string>
#include <vector>
#include <algorithm>
#include <numeric>

// C layer declarations
extern "C" {
    // Aggregate results from multiple compute nodes
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

class ComputeTask {
public:
    std::string task_id;
    std::vector<int> data;
    std::string node_id;

    ComputeTask(const std::string& id, const std::string& node)
        : task_id(id), node_id(node) {}

    // Simulate computation on data
    int compute() {
        // Simulate some computation
        int sum = std::accumulate(data.begin(), data.end(), 0);
        int product = std::accumulate(data.begin(), data.end(), 1, std::multiplies<int>());
        return sum + product;
    }

    // Convert result to string
    std::string serialize_result(int result) {
        return "task=" + task_id + ";result=" + std::to_string(result);
    }
};

class DistributedComputeManager {
public:
    std::vector<ComputeTask> tasks;

    void add_task(const std::string& task_id, const std::string& node_id,
                  const std::vector<int>& data) {
        tasks.emplace_back(task_id, node_id);
        tasks.back().data = data;
    }

    // Process all tasks and aggregate results
    std::string process_all_tasks() {
        std::string all_results;

        for (auto& task : tasks) {
            std::cout << "[C++] Processing task " << task.task_id
                      << " on node " << task.node_id << std::endl;

            int result = task.compute();
            std::string serialized = task.serialize_result(result);

            std::cout << "[C++] Task result: " << serialized << std::endl;

            // Send to C layer for aggregation
            char aggregated_output[1024];
            int agg_result = c_aggregate_results(
                task.node_id.c_str(),
                serialized.c_str(),
                aggregated_output,
                sizeof(aggregated_output)
            );

            if (agg_result == 0) {
                all_results += std::string(aggregated_output) + ";";
            }
        }

        return all_results;
    }

    // Verify aggregated results against expected hash
    bool verify_results(const std::string& aggregated_data,
                       const std::string& expected_hash) {
        std::cout << "[C++] Verifying aggregated results..." << std::endl;

        char verification_result[512];
        int verify_result = c_verify_hash(
            aggregated_data.c_str(),
            expected_hash.c_str(),
            verification_result,
            sizeof(verification_result)
        );

        if (verify_result == 0) {
            std::cout << "[C++] Verification result: "
                      << verification_result << std::endl;
            return std::string(verification_result) == "VERIFIED";
        }

        return false;
    }

    // Execute final command based on verification
    void execute_final_command(const std::string& command,
                              const std::string& token) {
        std::cout << "[C++] Executing final command: " << command << std::endl;

        int exec_result = c_execute_command(
            command.c_str(),
            token.c_str()
        );

        if (exec_result == 0) {
            std::cout << "[C++] Command executed successfully" << std::endl;
        } else {
            std::cout << "[C++] Command execution failed" << std::endl;
        }
    }
};

// Main entry point - simulates a distributed computing job
int main(int argc, char* argv[]) {
    std::cout << "=== Distributed Computing System ===" << std::endl;
    std::cout << "C++: Business logic and data processing" << std::endl;
    std::cout << "C: Result aggregation and verification" << std::endl << std::endl;

    DistributedComputeManager manager;

    // Scenario 1: Normal compute tasks
    std::cout << "[Scenario 1] Normal compute tasks:" << std::endl;
    manager.add_task("task_001", "node_01", {1, 2, 3, 4, 5});
    manager.add_task("task_002", "node_02", {10, 20, 30, 40, 50});

    std::string aggregated = manager.process_all_tasks();
    std::cout << "[C++] Aggregated results: " << aggregated << std::endl;

    bool verified = manager.verify_results(aggregated, "a1b2c3d4");
    if (verified) {
        manager.execute_final_command("deploy", "token_12345");
    }
    std::cout << std::endl;

    // Scenario 2: User-controlled input (VULNERABLE)
    std::cout << "[Scenario 2] User-controlled input:" << std::endl;
    manager.add_task("task_003", "node_03", {100, 200, 300});

    std::string user_input = "special_command";  // User input
    std::cout << "[C++] User input: " << user_input << std::endl;

    // This user input flows to C layer - VULNERABLE!
    manager.execute_final_command(user_input, "token_67890");

    std::cout << "\n[C++] WARNING: User input flows to C layer without proper validation!" << std::endl;

    return 0;
}