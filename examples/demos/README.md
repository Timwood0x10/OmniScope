# C++ + C Cross-Language FFI Demo

## Overview

This is a **working** cross-language demo demonstrating how C++'s type safety can be undermined by vulnerabilities in a C library accessed via `extern "C"`.

### Why This Works

Unlike Rust + C or Go + C, this approach works because:
1. Both C++ and C generate LLVM IR natively
2. `extern "C"` properly handles FFI calls between languages
3. Can be compiled together into a single LLVM IR file
4. No need for special toolchains or third-party compilers

### Scenario

A production application built with C++ uses a legacy C library for critical operations. The C++ layer performs input validation and type checking, but the C library contains vulnerabilities that can be triggered by malicious input.

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                   C++ Application Layer                  │
│  (Type Safe, Input Validation, Exception Handling)      │
│                                                           │
│  • InputValidator class (regex checks, pattern matching)│
│  • SafeProcessor class (type-safe wrappers)             │
│  • Exception handling                                   │
└─────────────────┬───────────────────────────────────────┘
                  │ extern "C" Boundary
                  │ (Unsafe)
                  ▼
┌─────────────────────────────────────────────────────────┐
│                      C Library                           │
│  (No Type Safety, Memory Unsafe)                        │
│                                                           │
│  • c_process_input()   [Buffer overflow vulnerability]  │
│  • c_execute_command() [Command injection vulnerability]│
│  • c_parse_config()    [Buffer overflow vulnerability]  │
└─────────────────────────────────────────────────────────┘
```

## Vulnerabilities

### 1. Buffer Overflow in `c_process_input()`

**C++ code (appears safe):**
```cpp
bool InputValidator::validate(const std::string& input) {
    if (input.empty() || input.length() > 256) {
        return false;  // C++ validation
    }
    // Additional validation...
    return true;
}

std::string SafeProcessor::process(const std::string& user_input) {
    if (!InputValidator::validate(user_input)) {
        throw std::runtime_error("Input validation failed");
    }
    // Call C function
    c_process_input(user_input.c_str(), output_buffer, sizeof(output_buffer));
}
```

**C code (vulnerable):**
```c
int c_process_input(const char* input, char* output, int output_size) {
    strcpy(output, "Processed: ");
    strcat(output, input);  // VULNERABILITY: No bounds checking!
    return 0;
}
```

**Attack Vector:**
```cpp
// Input with 512 characters will overflow 512-byte buffer
std::string malicious = std::string(512, 'A');
processor.process(malicious);  // Buffer overflow!
```

**Data Flow:**
```
User Input → C++ Validation (passes) → extern "C" → C Function → Buffer Overflow
```

### 2. Command Injection in `c_execute_command()`

**C++ code (appears safe):**
```cpp
bool InputValidator::validate(const std::string& input) {
    static const std::regex dangerous_chars("[|&;<>()$`\\\\]");
    if (std::regex_search(input, dangerous_chars)) {
        return false;  // C++ validation
    }
    return true;
}

void SafeProcessor::execute(const std::string& command) {
    if (!InputValidator::validate(command)) {
        throw std::runtime_error("Command validation failed");
    }
    // Call C function
    c_execute_command(command.c_str());
}
```

**C code (vulnerable):**
```c
int c_execute_command(const char* command) {
    char shell_command[512];
    // VULNERABILITY: Command not sanitized!
    snprintf(shell_command, sizeof(shell_command),
             "/usr/bin/%s --execute", command);
    return system(shell_command);  // Command injection!
}
```

**Attack Vector:**
```cpp
// Command injection through encoding
std::string malicious = "valid_name; rm -rf /";
// If C++ validation has bypass, this executes arbitrary command
processor.execute(malicious);
```

**Data Flow:**
```
User Input → C++ Validation (potentially bypassed) → extern "C" → system() → Command Execution
```

### 3. Buffer Overflow in `c_parse_config()`

**C++ code (appears safe):**
```cpp
std::string SafeProcessor::parseConfig(const std::string& config_data) {
    if (config_data.length() > 4096) {
        throw std::runtime_error("Config data too large");  // C++ validation
    }
    // Call C function
    c_parse_config(config_data.c_str(), parsed_result, sizeof(parsed_result));
}
```

**C code (vulnerable):**
```c
int c_parse_config(const char* config_data, char* parsed_result, int result_size) {
    strcpy(parsed_result, "Key: ");
    strcat(parsed_result, key);
    strcat(parsed_result, ", Value: ");
    strcat(parsed_result, value);  // VULNERABILITY: No bounds checking!
    return 0;
}
```

**Attack Vector:**
```cpp
// Very long key or value will overflow result buffer
std::string malicious = std::string(1024, 'A') + "=value";
processor.parseConfig(malicious);  // Buffer overflow!
```

**Data Flow:**
```
Config Data → C++ Validation (checks total length) → extern "C" → C Function → Buffer Overflow
```

## Building and Running

### Compile the C Library

```bash
cd examples/demos
gcc -c -emit-llvm -O0 -g c_vulnerable_layer.c -o c_vulnerable_layer.bc
```

### Compile the C++ Code

```bash
clang++ -c -emit-llvm -O0 -g cpp_ffi_safe_layer.cpp -o cpp_ffi_safe_layer.bc
```

### Link and Analyze

```bash
# Link the IR files
llvm-link cpp_ffi_safe_layer.bc c_vulnerable_layer.bc -o combined.bc

# Analyze with OmniScope
./zig-out/bin/OmniScope examples/demos/combined.bc
```

## Expected OmniScope Output

OmniScope should detect:

1. **Buffer Overflow Path:**
   ```
   [ERROR] VULNERABILITY OMI-001
   [ERROR] Severity: critical
   [ERROR] Path:
   [ERROR]   [Sink] c_process_input()
   [ERROR]     └─> strcat()  [Buffer overflow vulnerability]
   [ERROR]   [Source] main() - user input
   [ERROR] Impact: Remote code execution possible
   ```

2. **Command Injection Path:**
   ```
   [ERROR] VULNERABILITY OMI-002
   [ERROR] Severity: critical
   [ERROR] Path:
   [ERROR]   [Sink] c_execute_command()
   [ERROR]     └─> system()  [Command injection vulnerability]
   [ERROR]   [Source] main() - user input
   [ERROR] Impact: Arbitrary command execution
   ```

3. **Config Parser Buffer Overflow:**
   ```
   [ERROR] VULNERABILITY OMI-003
   [ERROR] Severity: critical
   [ERROR] Path:
   [ERROR]   [Sink] c_parse_config()
   [ERROR]     └─> strcat()  [Buffer overflow vulnerability]
   [ERROR]   [Source] main() - config data
   [ERROR] Impact: Remote code execution
   ```

4. **FFI Boundary Detection:**
   ```
   [INFO] FFI Boundary detected: C++ → C
   [INFO] Taint propagates across extern "C" boundary
   [WARN] C++ validation does not protect C layer from vulnerabilities
   ```

## Key Takeaways

1. **C++ type safety does not extend across extern "C" boundaries**
2. **Input validation in C++ does not prevent vulnerabilities in C code**
3. **Legacy C libraries wrapped by C++ can be a security blind spot**
4. **Cross-language taint tracking is critical for FFI security**
5. **Exception handling in C++ cannot catch C-level crashes**

## Real-World Parallels

This scenario is common in:
- **Financial systems**: C++ application layer with OpenSSL C library
- **Game engines**: C++ game logic with C physics/audio libraries
- **Embedded systems**: C++ control plane with C hardware drivers
- **Cloud infrastructure**: C++ services with C networking libraries

## Comparison: Cross-Language Approaches

| Approach | LLVM IR Support | FFI Handling | Tooling | Status |
|----------|----------------|--------------|---------|--------|
| **C++ + C** | ✅ Native | ✅ extern "C" | ✅ clang++/gcc | ✅ **WORKING** |
| Rust + C | ✅ Native | ❌ Declare only | ✅ rustc | ❌ Non-working |
| Go + C | ❌ No official | ❌ CGO only | ❌ gollvm (unstable) | ❌ Non-working |
| Zig + C | ✅ Native | ✅ @cImport | ✅ zig | ✅ Working |

## Mitigation Strategies

1. **Implement input validation in BOTH C++ and C layers**
2. **Use safe string functions in C (strlcpy, strlcat)**
3. **Sandbox C code with seccomp, chroot, or containers**
4. **Prefer pure C++ implementations when performance allows**
5. **Employ fuzz testing across FFI boundaries**
6. **Use tools like OmniScope for cross-language vulnerability detection**

## Why This Approach Is Better

Unlike the Rust + C or Go + C demos:

1. **No special toolchains required** - Uses standard clang++ and gcc
2. **Works reliably** - Both languages support LLVM IR generation
3. **Real FFI calls** - extern "C" creates actual cross-language call graph
4. **Production-ready** - Matches real-world C++ + C integration patterns
5. **Easy to debug** - Can examine IR and verify cross-language calls

## Running the Demo

```bash
cd /Users/scc/code/zigcode/OmniSope

# Compile C layer
gcc -c -emit-llvm -O0 -g examples/demos/c_vulnerable_layer.c -o c_vulnerable_layer.bc

# Compile C++ layer
clang++ -c -emit-llvm -O0 -g examples/demos/cpp_ffi_safe_layer.cpp -o cpp_ffi_safe_layer.bc

# Link
llvm-link c_vulnerable_layer.bc cpp_ffi_safe_layer.bc -o combined.bc

# Analyze
zig-out/bin/OmniScope combined.bc
```

Or use the script:
```bash
./scripts/run_examples.sh cpp_ffi
```