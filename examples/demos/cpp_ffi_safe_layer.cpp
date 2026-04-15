// C++ Safe Layer with C FFI
//
// SCENARIO: A production application using C++ for the business logic,
// but delegating critical operations to a C library via extern "C".
// The C++ layer provides input validation and type safety, but the C layer
// has vulnerabilities that can be exploited.
//
// This is a REAL and WORKING cross-language demo because:
// 1. C++ and C both generate LLVM IR
// 2. extern "C" properly handles FFI calls
// 3. Can be compiled together into a single LLVM IR file

#include <iostream>
#include <string>
#include <vector>
#include <regex>

// C library declarations (vulnerable layer)
extern "C" {
    // Process user input - VULNERABLE in C layer
    int c_process_input(const char* input, char* output, int output_size);

    // Execute command - VULNERABLE in C layer
    int c_execute_command(const char* command);

    // Parse configuration - VULNERABLE in C layer
    int c_parse_config(const char* config_data, char* parsed_result, int result_size);
}

class InputValidator {
public:
    // Validate user input at C++ layer
    static bool validate(const std::string& input) {
        // C++ validation: check length
        if (input.empty() || input.length() > 256) {
            std::cerr << "[C++] Input length invalid" << std::endl;
            return false;
        }

        // C++ validation: check for dangerous characters
        static const std::regex dangerous_chars("[|&;<>()$`\\\\]");
        if (std::regex_search(input, dangerous_chars)) {
            std::cerr << "[C++] Dangerous characters detected" << std::endl;
            return false;
        }

        // C++ validation: check for command injection patterns
        static const std::vector<std::string> dangerous_patterns = {
            "rm -rf", "sudo", "nc -l", "> /dev", "eval(", "$("
        };

        for (const auto& pattern : dangerous_patterns) {
            if (input.find(pattern) != std::string::npos) {
                std::cerr << "[C++] Dangerous pattern detected: " << pattern << std::endl;
                return false;
            }
        }

        return true;
    }
};

class SafeProcessor {
public:
    // Process user input using C++ validation
    std::string process(const std::string& user_input) {
        std::cout << "[C++] Processing input: " << user_input << std::endl;

        // C++ validation
        if (!InputValidator::validate(user_input)) {
            throw std::runtime_error("Input validation failed");
        }

        // Call C function (VULNERABLE)
        char output_buffer[512];
        int result = c_process_input(user_input.c_str(), output_buffer, sizeof(output_buffer));

        if (result != 0) {
            throw std::runtime_error("C processing failed");
        }

        std::cout << "[C++] C processing completed" << std::endl;
        return std::string(output_buffer);
    }

    // Execute command using C++ validation
    void execute(const std::string& command) {
        std::cout << "[C++] Executing command: " << command << std::endl;

        // C++ validation
        if (!InputValidator::validate(command)) {
            throw std::runtime_error("Command validation failed");
        }

        // Call C function (VULNERABLE)
        int result = c_execute_command(command.c_str());

        if (result != 0) {
            throw std::runtime_error("Command execution failed");
        }

        std::cout << "[C++] Command executed successfully" << std::endl;
    }

    // Parse configuration using C++ validation
    std::string parseConfig(const std::string& config_data) {
        std::cout << "[C++] Parsing configuration" << std::endl;

        // C++ validation
        if (config_data.length() > 4096) {
            throw std::runtime_error("Config data too large");
        }

        // Call C function (VULNERABLE)
        char parsed_result[1024];
        int result = c_parse_config(config_data.c_str(), parsed_result, sizeof(parsed_result));

        if (result != 0) {
            throw std::runtime_error("Config parsing failed");
        }

        std::cout << "[C++] Config parsed successfully" << std::endl;
        return std::string(parsed_result);
    }
};

// Main application - simulates a production service
int main(int argc, char* argv[]) {
    std::cout << "=== C++ Application with C FFI ===" << std::endl;
    std::cout << "C++ provides type safety, but C layer has vulnerabilities" << std::endl << std::endl;

    SafeProcessor processor;

    try {
        // Scenario 1: Normal input (should work)
        std::cout << "[Scenario 1] Normal input:" << std::endl;
        std::string result1 = processor.process("normal_user_input");
        std::cout << "[C++] Result: " << result1 << std::endl << std::endl;

        // Scenario 2: Input with dangerous characters (C++ validation catches this)
        std::cout << "[Scenario 2] Input with dangerous characters:" << std::endl;
        try {
            std::string result2 = processor.process("input; rm -rf /");
        } catch (const std::exception& e) {
            std::cout << "[C++] Caught: " << e.what() << std::endl;
        }
        std::cout << std::endl;

        // Scenario 3: Command execution (C++ validation, but C layer is vulnerable)
        std::cout << "[Scenario 3] Command execution:" << std::endl;
        try {
            processor.execute("list_files");
        } catch (const std::exception& e) {
            std::cout << "[C++] Caught: " << e.what() << std::endl;
        }
        std::cout << std::endl;

        // Scenario 4: Config parsing (C++ validation, but C layer is vulnerable)
        std::cout << "[Scenario 4] Config parsing:" << std::endl;
        try {
            std::string config_result = processor.parseConfig("key=value;option=true");
            std::cout << "[C++] Config: " << config_result << std::endl;
        } catch (const std::exception& e) {
            std::cout << "[C++] Caught: " << e.what() << std::endl;
        }

        std::cout << "\n[C++] WARNING: C layer vulnerabilities may bypass C++ validation!" << std::endl;

    } catch (const std::exception& e) {
        std::cerr << "[C++] Fatal error: " << e.what() << std::endl;
        return 1;
    }

    return 0;
}
