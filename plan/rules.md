# Zig Coding Standards

## Version: 1.0

## Last Updated: April 16, 2026

***

## Table of Contents

1. [Overview](#overview)
2. [File Structure and Size Limits](#file-structure-and-size-limits)
3. [Code and Comment Standards](#code-and-comment-standards)
4. [Testing Requirements](#testing-requirements)
5. [API Design Principles](#api-design-principles)
6. [Zig Official Standards Compliance](#zig-official-standards-compliance)
7. [Naming Conventions](#naming-conventions)
8. [Code Organization](#code-organization)
9. [Error Handling](#error-handling)
10. [Memory Management](#memory-management)
11. [Performance Guidelines](#performance-guidelines)
12. [Documentation Standards](#documentation-standards)
13. [Code Review Guidelines](#code-review-guidelines)

***

## Overview

This document establishes coding standards for Zig projects to ensure code quality, maintainability, and consistency across the codebase. All team members must adhere to these standards.

**Core Principles:**

- Write clear, readable, and maintainable code
- Prioritize correctness over cleverness
- Test thoroughly with real-world scenarios
- Document intent, not just mechanics
- Follow Zig's philosophy of explicit behavior
- **Follow Zig official coding standards and style guide**
- **Design simple, concise APIs that are easy to understand and use**
- 禁止用 OmniScope.log.\* 用std.log 代替
- 强制要求用LLVM 22 

***

## File Structure and Size Limits

### Maximum File Size

**Rule:** Single file code line count must not exceed 1000 lines (including test code, common code, and implementation code).

**Rationale:**

- Large files are difficult to navigate and understand
- Smaller files promote better separation of concerns
- Easier code review and maintenance
- Reduces merge conflicts

**Implementation Guidelines:**

1. **File Size Calculation**
   - Count all lines including: implementation, tests, imports, comments
   - Exclude blank lines from the count
   - Use tooling to enforce this limit in CI/CD
2. **File Splitting Strategy**
   - Split large files by logical functionality
   - Create separate modules for distinct concerns
   - Move test code to dedicated test files when approaching limits
   - Extract common utilities to shared modules
3. **Examples of Acceptable File Organization**
   ```
   src/
   ├── main.zig              (entry point, <500 lines)
   ├── core/
   │   ├── types.zig        (type definitions, <300 lines)
   │   ├── utils.zig        (utility functions, <400 lines)
   │   └── constants.zig    (constants, <200 lines)
   └── test/
       ├── main_test.zig    (main tests, <500 lines)
       └── utils_test.zig   (utils tests, <500 lines)
   ```
4. **Enforcement**
   - Configure pre-commit hooks to check file sizes
   - Fail CI builds if files exceed 1000 lines
   - Require justification for exceptions (rare and temporary)

***

## Code and Comment Standards

### Code-to-Comment Ratio

**Rule:** Maintain a code-to-comment ratio of 7:3. For every 7 lines of code, there should be approximately 3 lines of comments.

**Rationale:**

- Comments explain intent and design decisions
- Helps future maintainers understand complex logic
- Facilitates knowledge transfer between team members
- Reduces technical debt

**Implementation Guidelines:**

1. **Comment Types and Usage**

   **a) Documentation Comments (///)**
   ```zig
   /// Performs binary search on a sorted array.
   /// Returns the index of the target value, or null if not found.
   /// Time complexity: O(log n)
   ///
   /// Arguments:
   ///   - array: Sorted array to search
   ///   - target: Value to find
   ///
   /// Returns:
   ///   Index of target, or null if not present
   fn binarySearch(array: []const i32, target: i32) ?usize {
       // Implementation...
   }
   ```
   **b) Inline Comments (//)**
   ```zig
   // Use two-pointer technique for O(n) time complexity
   var left: usize = 0;
   var right: usize = array.len - 1;

   // Early exit if array is empty
   if (array.len == 0) return null;
   ```
   **c) Block Comments for Complex Logic**
   ```zig
   // Calculate Fibonacci number using memoization
   // to achieve O(n) time complexity instead of O(2^n)
   // recursive approach. This is critical for performance
   // with large input values.
   fn fibonacci(n: usize, memo: *std.AutoHashMap(usize, usize)) !usize {
       // Implementation...
   }
   ```
2. **What to Comment**
   - **WHY** something is done, not just WHAT
   - Non-obvious algorithms and their complexity
   - Design decisions and trade-offs
   - Workarounds for known issues
   - Performance-critical sections
   - Error handling strategies
3. **What NOT to Comment**
   - Obvious code (e.g., `i += 1; // increment i`)
   - Code that can be made self-documenting
   - Outdated or incorrect comments
   - Commented-out code (delete it instead)
4. **Comment Language**
   - **All comments must be in English**
   - Use clear, professional language
   - Avoid slang and abbreviations
   - Spell check comments in code review
5. **Example of Proper Ratio**
   ```zig
   // Total: 10 lines (7 code, 3 comments) - 70% code, 30% comments

   /// Validates user input according to business rules.
   /// This function ensures data integrity before processing.
   fn validateInput(input: []const u8) !bool {
       // Check minimum length requirement
       if (input.len < MIN_LENGTH) {
           return error.TooShort;
       }
       
       // Verify character set is allowed
       for (input) |char| {
           if (!isAllowedChar(char)) {
               return error.InvalidCharacter;
           }
       }
       
       return true;
   }
   ```

***

## Testing Requirements

### Test Coverage

**Rule:** Project test coverage must not be less than 85%.

**Rationale:**

- High coverage ensures code reliability
- Catches regressions early
- Facilitates refactoring with confidence
- Provides living documentation

**Implementation Guidelines:**

1. **Coverage Measurement**
   - Use Zig's built-in test coverage tools
   - Generate coverage reports in CI/CD
   - Fail builds if coverage drops below 85%
   - Track coverage trends over time
2. **Coverage Requirements by Component**
   - Core business logic: 95%+ coverage
   - Utility functions: 90%+ coverage
   - Error handling paths: 100% coverage
   - Edge cases and boundary conditions: 100% coverage
3. **Test Case Requirements**

   **a) Real Test Cases Only**
   ```zig
   // GOOD: Real-world scenario
   test "processPayment with valid credit card" {
       const card = CreditCard{
           .number = "4111111111111111",
           .expiry = "12/25",
           .cvv = "123",
       };
       const result = try processPayment(card, 100.00);
       try testing.expect(result.status == .approved);
   }

   // BAD: Mock data without context
   test "processPayment with mock data" {
       const mock_data = [_]u8{1, 2, 3, 4, 5}; // What does this represent?
       const result = try processPayment(mock_data);
       try testing.expect(result == true);
   }
   ```
   **b) No Extensive Mock Data**
   - Use real data structures and values
   - Avoid arrays of meaningless numbers
   - Create realistic test fixtures
   - Document why specific values are used
   ```zig
   // GOOD: Meaningful test data
   const VALID_USER = User{
       .id = 1,
       .username = "john_doe",
       .email = "john@example.com",
       .role = .admin,
   };

   // BAD: Arbitrary mock data
   const MOCK_USER = [_]u8{0x01, 0x02, 0x03, 0x04};
   ```
   **c) No敷衍 Implementation**
   - Each test must have a clear purpose
   - Test meaningful scenarios, not just to increase coverage
   - Verify actual behavior, not just that code runs
   - Include assertions that check expected outcomes
   ```zig
   // GOOD: Meaningful test with clear assertions
   test "calculateDiscount returns correct percentage" {
       const price: f32 = 100.0;
       const discount = calculateDiscount(price, .premium);
       try testing.expectEqual(@as(f32, 15.0), discount);
       try testing.expect(discount < price);
   }

   // BAD:敷衍 test that just runs code
   test "calculateDiscount runs" {
       _ = calculateDiscount(100.0, .premium); // No assertions!
   }
   ```
4. **Test Organization**
   ```zig
   // Group related tests
   const std = @import("std");
   const testing = std.testing;

   const Calculator = @import("calculator.zig");

   test "Calculator.addition" {
       try testing.expectEqual(@as(i32, 5), Calculator.add(2, 3));
   }

   test "Calculator.subtraction" {
       try testing.expectEqual(@as(i32, -1), Calculator.subtract(2, 3));
   }

   test "Calculator.edge cases" {
       // Test overflow behavior
       try testing.expectError(error.Overflow, Calculator.add(@as(i32, 2147483647), 1));
   }
   ```
5. **Test Naming Convention**
   - Use descriptive test names
   - Format: `test "FeatureName scenario"` or `test "Component.action expected"`
   - Include what is being tested and the expected outcome
6. **Integration vs Unit Tests**
   - Maintain both unit and integration tests
   - Unit tests: Fast, isolated, test individual functions
   - Integration tests: Slower, test component interactions
   - Aim for 70% unit tests, 30% integration tests

***

## API Design Principles

### Core Principle: Simplicity and Conciseness

**Rule:** API design must be simple, concise, and easy to understand. Avoid unnecessary complexity and follow Zig's philosophy of minimalism.

**Rationale:**

- Simple APIs are easier to learn and use correctly
- Concise interfaces reduce cognitive load
- Fewer parameters mean fewer errors
- Consistent design patterns improve discoverability

**Implementation Guidelines:**

1. **Function Design**

   **a) Minimal Parameters**
   ```zig
   // GOOD: Minimal, focused parameters
   fn readFile(path: []const u8) ![]u8 { ... }

   // BAD: Too many parameters, confusing
   fn readFile(
       path: []const u8,
       buffer: []u8,
       offset: usize,
       flags: u32,
       callback: fn ([]u8) void,
   ) !usize { ... }
   ```
   **b) Use Options for Optional Parameters**
   ```zig
   // GOOD: Optional parameter clearly marked
   fn connect(host: []const u8, port: ?u16) !Connection {
       const actual_port = port orelse 8080;
       // ...
   }

   // BAD: Overloaded functions for optional parameters
   fn connectDefaultPort(host: []const u8) !Connection { ... }
   fn connectWithPort(host: []const u8, port: u16) !Connection { ... }
   ```
   **c) Single Responsibility**
   ```zig
   // GOOD: Each function does one thing well
   fn validateEmail(email: []const u8) bool { ... }
   fn sendEmail(to: []const u8, subject: []const u8, body: []const u8) !void { ... }

   // BAD: Function does too many things
   fn processEmail(email: []const u8) !void {
       // Validates, parses, sends, logs, archives...
   }
   ```
2. **Type Design**

   **a) Prefer Simple Types**
   ```zig
   // GOOD: Simple, clear types
   const UserId = u32;
   const Timestamp = i64;

   // BAD: Overly complex types for simple concepts
   const UserId = struct {
       value: u64,
       version: u8,
       checksum: u16,
   };
   ```
   **b) Use Enums for Fixed Sets**
   ```zig
   // GOOD: Clear, type-safe options
   const Color = enum { red, green, blue };

   // BAD: Magic numbers or strings
   const RED = 0;
   const GREEN = 1;
   const BLUE = 2;
   ```
   **c) Avoid Deep Nesting**
   ```zig
   // GOOD: Flat structure
   const Config = struct {
       host: []const u8,
       port: u16,
       timeout: u32,
   };

   // BAD: Deeply nested structures
   const Config = struct {
       network: struct {
           host: struct {
               primary: []const u8,
               secondary: ?struct {
                   address: []const u8,
                   port: u16,
               },
           },
       },
   };
   ```
3. **Error Handling in APIs**

   **a) Meaningful Error Sets**
   ```zig
   // GOOD: Specific, actionable errors
   const FileError = error{
       NotFound,
       PermissionDenied,
       OutOfMemory,
   };

   // BAD: Generic, unhelpful errors
   const FileError = error{
       Failed,
       Error,
       Bad,
   };
   ```
   **b) Document All Possible Errors**
   ```zig
   /// Opens a file for reading.
   ///
   /// Errors:
   ///   - FileNotFound: Path does not exist
   ///   - PermissionDenied: Insufficient permissions
   ///   - OutOfMemory: Cannot allocate buffer
   fn openFile(path: []const u8) !File { ... }
   ```
4. **Naming and Consistency**

   **a) Consistent Naming Patterns**
   ```zig
   // GOOD: Consistent verb-noun pattern
   fn getUser(id: UserId) ?User { ... }
   fn createUser(user: User) !UserId { ... }
   fn updateUser(id: UserId, user: User) !void { ... }
   fn deleteUser(id: UserId) !void { ... }

   // BAD: Inconsistent naming
   fn getUser(id: UserId) ?User { ... }
   fn makeUser(user: User) !UserId { ... }
   fn modifyUser(id: UserId, user: User) !void { ... }
   fn removeUser(id: UserId) !void { ... }
   ```
   **b) Self-Documenting Names**
   ```zig
   // GOOD: Name explains purpose
   fn calculateDistance(point1: Point, point2: Point) f32 { ... }

   // BAD: Vague name requires documentation
   fn compute(p1: Point, p2: Point) f32 { ... }
   ```
5. **Documentation**

   **a) Clear, Concise Documentation**
   ```zig
   /// Converts temperature from Celsius to Fahrenheit.
   /// Returns the converted temperature value.
   fn celsiusToFahrenheit(celsius: f32) f32 { ... }
   ```
   **b) Provide Examples**
   ````zig
   /// Creates a new HTTP client with default settings.
   ///
   /// Example:
   /// ```zig
   /// const client = try HttpClient.init();
   /// defer client.deinit();
   /// const response = try client.get("https://example.com");
   /// ```
   fn init() !HttpClient { ... }
   ````
6. **API Evolution**

   **a) Prefer Adding Over Deprecating**
   ```zig
   // When extending functionality, add new functions
   // rather than changing existing ones
   fn parse(input: []const u8) !Value { ... }
   fn parseStrict(input: []const u8) !Value { ... }  // New variant
   ```
   **b) Document Deprecated APIs**
   ```zig
   /// Deprecated: Use parseStrict() instead.
   /// This function will be removed in version 2.0.
   fn parse(input: []const u8) !Value { ... }
   ```

***

## Zig Official Standards Compliance

### Mandatory Compliance

**Rule:** All code must strictly follow Zig official coding standards and style guide as documented in the Zig language reference.

**Rationale:**

- Ensures consistency with the broader Zig ecosystem
- Leverages community best practices
- Makes code easier for other Zig developers to understand
- Reduces learning curve for new team members

**Implementation Guidelines:**

1. **Follow Zig Style Guide**
   - Reference: <https://ziglang.org/documentation/master/#Style-Guide>
   - Adhere to formatting conventions (4-space indentation, etc.)
   - Follow naming conventions from the standard library
   - Use idiomatic Zig patterns
2. **Standard Library Alignment**
   ```zig
   // GOOD: Follows std library patterns
   fn processItems(items: []const Item) !void {
       for (items) |item| {
           try processItem(item);
       }
   }

   // BAD: Non-idiomatic patterns
   fn processItems(items: []const Item) !void {
       var i: usize = 0;
       while (i < items.len) : (i += 1) {
           try processItem(items[i]);
       }
   }
   ```
3. **Use Standard Library Types**
   ```zig
   // GOOD: Use standard library types when appropriate
   const ArrayList = std.ArrayList;
   const HashMap = std.HashMap;

   // BAD: Reimplement standard library functionality
   const MyList = struct { /* reinvents ArrayList */ };
   ```
4. **Follow Zig Error Handling Conventions**
   - Use error unions for fallible operations
   - Document all possible errors
   - Use `try`, `catch`, and `orelse` idiomatically
   - Prefer explicit error handling over silent failures
5. **Memory Management**
   - Follow Zig's ownership model
   - Use allocators explicitly
   - Clean up resources with `defer`
   - Document lifetime requirements
6. **Build System Integration**
   - Use `build.zig` for project configuration
   - Follow Zig package conventions
   - Properly declare dependencies
   - Use standard build options
7. **Testing Conventions**
   - Use Zig's built-in test framework
   - Follow `test "description" { ... }` pattern
   - Use `std.testing` assertions
   - Organize tests alongside source code
8. **Documentation Format**
   - Use `///` for documentation comments
   - Follow Zig doc comment conventions
   - Include examples in documentation
   - Document all public APIs
9. **Compiler Warnings**
   - Treat all compiler warnings as errors
   - Address `-W` and `-Werror` flags
   - Fix all linting issues
   - Use `zig fmt` for code formatting
10. **Version Compatibility**
    - Specify minimum Zig version in `build.zig`
    - Test with supported Zig versions
    - Avoid using experimental features in production
    - Document version-specific requirements

**Verification:**

- Run `zig fmt` on all files before commit
- Use `zig build test` to ensure all tests pass
- Check with `zig build -Denable-docs` for documentation
- Verify no compiler warnings with `-Werror`
- Use `zig vet` if available for additional checks

**Resources:**

- [Zig Language Reference](https://ziglang.org/documentation/master/)
- [Zig Standard Library](https://ziglang.org/documentation/master/std/)
- [Zig Style Guide](https://ziglang.org/documentation/master/#Style-Guide)
- [Zig Code Samples](https://ziglang.org/documentation/master/#Samples)

***

## Naming Conventions

### General Rules

- Use clear, descriptive names
- Avoid abbreviations unless widely known
- Be consistent across the codebase
- Follow Zig's standard library conventions

### Specific Conventions

1. **Variables and Functions**: `snake_case`
   ```zig
   var user_name: []const u8 = "john";
   fn calculate_total(price: f32, tax: f32) f32 { ... }
   ```
2. **Constants and Types**: `PascalCase`
   ```zig
   const MaxBufferSize = 4096;
   const UserAccount = struct { ... };
   const ErrorCode = enum { ... };
   ```
3. **Acronyms**: Treat as words (e.g., `HttpServer` not `HTTPServer`)
   ```zig
   const XmlDocument = struct { ... };  // not XMLDocument
   fn parse_http_response(...) { ... }   // not parseHTTPResponse
   ```
4. **Private Members**: Prefix with `_`
   ```zig
   const InternalState = struct {
       _private_field: u32,
       public_field: u32,
   };
   ```
5. **Error Sets**: `PascalCase` with descriptive names
   ```zig
   const FileSystemError = error{
       FileNotFound,
       PermissionDenied,
       DiskFull,
   };
   ```

***

## Code Organization

### Module Structure

```
project/
├── build.zig
├── src/
│   ├── main.zig           # Entry point
│   ├── core/              # Core functionality
│   │   ├── types.zig
│   │   ├── errors.zig
│   │   └── constants.zig
│   ├── utils/             # Utility functions
│   │   ├── string.zig
│   │   └── math.zig
│   └── api/               # External interfaces
│       └── client.zig
├── test/                  # Test files
│   ├── core_test.zig
│   └── utils_test.zig
└── docs/                  # Documentation
    └── api.md
```

### Import Order

```zig
// 1. Standard library
const std = @import("std");

// 2. Local modules (alphabetical)
const core = @import("core/types.zig");
const utils = @import("utils/string.zig");

// 3. Third-party dependencies
const zjson = @import("zjson");
```

***

## Error Handling

### Principles

- Handle errors explicitly
- Use error unions (`!T`) for fallible operations
- Provide meaningful error messages
- Document all possible errors in function docs

### Guidelines

```zig
// Good: Explicit error handling
fn readFile(path: []const u8) ![]u8 {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    
    const contents = try file.readAllAlloc(std.heap.page_allocator, 1024 * 1024);
    return contents;
}

// Good: Document errors
/// Opens and reads a file.
/// 
/// Errors:
///   - FileNotFound: File does not exist at path
///   - PermissionDenied: Insufficient permissions
///   - OutOfMemory: Allocation failed
fn readFile(path: []const u8) ![]u8 { ... }

// Good: Use catch for recovery
const contents = readFile(path) catch |err| {
    std.log.err("Failed to read file: {}", .{err});
    return &empty_buffer;
};
```

***

## Memory Management

### Principles

- Prefer stack allocation when possible
- Use allocators explicitly
- Always clean up resources (defer)
- Document ownership semantics

### Guidelines

```zig
// Good: Stack allocation
fn processSmallData(data: [128]u8) void {
    var buffer: [256]u8 = undefined;
    // Process data...
}

// Good: Explicit allocator usage
fn processData(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    const result = try allocator.alloc(u8, input.len * 2);
    errdefer allocator.free(result);
    
    // Process data...
    return result;
}

// Good: Resource cleanup with defer
fn processFile(path: []const u8) !void {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    
    const contents = try file.readAllAlloc(std.heap.page_allocator, 1024);
    defer std.heap.page_allocator.free(contents);
    
    // Process file...
}
```

***

## Performance Guidelines

### Principles

- Profile before optimizing
- Prefer readability over micro-optimizations
- Document performance-critical code
- Use appropriate data structures

### Guidelines

1. **Algorithm Selection**
   - Choose algorithms based on expected input size
   - Document time and space complexity
   - Consider worst-case scenarios
2. **Memory Efficiency**
   - Reuse buffers when possible
   - Use appropriate integer types (u8 vs u32 vs u64)
   - Avoid unnecessary allocations
3. **Hot Path Optimization**
   - Profile to identify bottlenecks
   - Optimize only measured hot paths
   - Document optimizations with before/after metrics

```zig
// Document performance characteristics
/// Performs O(n log n) sort using quicksort algorithm.
/// Optimized for typical use case with partially sorted input.
/// Memory usage: O(log n) for recursion stack.
fn sortArray(array: []i32) void {
    // Implementation...
}
```

***

## Documentation Standards

### Function Documentation

````zig
/// Brief one-line description of the function.
///
/// Detailed description explaining what the function does,
/// why it exists, and any important considerations.
///
/// Arguments:
///   - param1: Description of first parameter
///   - param2: Description of second parameter
///
/// Returns:
///   Description of return value and its meaning
///
/// Errors:
///   - ErrorOne: When this error occurs
///   - ErrorTwo: When that error occurs
///
/// Example:
///   ```zig
///   const result = try myFunction(arg1, arg2);
///   ```
///
/// Time Complexity: O(n)
/// Space Complexity: O(1)
fn myFunction(param1: Type1, param2: Type2) !ReturnType {
    // Implementation
}
````

### Module Documentation

````zig
//! Module description explaining its purpose.
//!
//! This module provides functionality for X.
//! It is used when you need to Y.
//!
//! # Examples
//!
//! ```zig
//! const my_module = @import("my_module");
//! const result = try my_module.doSomething();
//! ```
//!
//! # Thread Safety
//!
//! This module is thread-safe if...
//!
//! # Performance
//!
//! Operations in this module have O(n) complexity.
````

***

## Code Review Guidelines

### Review Checklist

- [ ] File size under 1000 lines
- [ ] Code-to-comment ratio approximately 7:3
- [ ] All comments are in English
- [ ] Test coverage ≥ 85%
- [ ] Tests use real scenarios (no extensive mocks)
- [ ] Tests have meaningful assertions
- [ ] Naming follows conventions
- [ ] Errors are properly handled
- [ ] Memory is properly managed
- [ ] Performance is considered where relevant
- [ ] Documentation is complete and accurate

### Review Process

1. **Self-Review**
   - Run all tests
   - Check coverage
   - Verify file sizes
   - Review comments
2. **Peer Review**
   - At least one approval required
   - Address all feedback
   - Update documentation as needed
3. **CI/CD Validation**
   - Automated checks run on every PR
   - Failing checks must be fixed before merge
   - Coverage reports generated automatically

***

## Enforcement

### Tools

- Pre-commit hooks for file size and comment ratio
- CI/CD pipeline for test coverage
- Linters for naming conventions
- Documentation generators

### Consequences

- Non-compliant code will not be merged
- Repeated violations require additional training
- Standards updated annually based on team feedback

***

## Appendix

### Resources

- [Zig Language Reference](https://ziglang.org/documentation/master/)
- [Zig Standard Library](https://ziglang.org/documentation/master/std/)
- [Zig Style Guide](https://ziglang.org/documentation/master/#Style-Guide)

### Changelog

- v1.0 (2026-04-16): Initial version

