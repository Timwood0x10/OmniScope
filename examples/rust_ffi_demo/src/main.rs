//! OmniScope Killer Demo - Main Entry Point
//!
//! This program demonstrates a cross-language security vulnerability:
//! - Rust code appears to be "safe" with sanitization
//! - C code has buffer overflow and command injection vulnerabilities
//! - OmniScope should detect these issues across the FFI boundary

use std::io::{self, BufRead, Write};

mod lib;

fn print_banner() {
    println!(r#"
╔══════════════════════════════════════════════════════════════╗
║           OmniScope Cross-Language Security Demo             ║
║                                                              ║
║  This demonstrates vulnerabilities that ONLY appear when      ║
║  analyzing Rust + C together:                                ║
║                                                              ║
║  1. Command Injection via FFI                                ║
║  2. Buffer Overflow across language boundary                 ║
║  3. Memory ownership confusion                               ║
║                                                              ║
║  Run OmniScope on the compiled IR to detect these issues!    ║
╚══════════════════════════════════════════════════════════════╝
"#);
}

fn main() {
    print_banner();

    println!("Enter a command (or 'quit' to exit):");
    println!("Hint: Try 'ls' or 'ls && pwd' to see the vulnerability");
    println!();

    let stdin = io::stdin();
    let mut stdout = io::stdout();

    for line in stdin.lock().lines() {
        match line {
            Ok(input) => {
                if input == "quit" || input == "exit" {
                    println!("Goodbye!");
                    break;
                }

                if input.is_empty() {
                    continue;
                }

                println!("\n[Processing through Rust -> C FFI...]");
                println!("Input: {}", input);

                // This looks safe - Rust "sanitizes" the input
                // But the C code is still vulnerable!
                match lib::process_input(&input) {
                    Ok(()) => println!("[OK] Command processed"),
                    Err(e) => println!("[ERROR] {}", e),
                }

                // Also demonstrate buffer overflow
                println!("\n[Testing buffer overflow...]");
                match lib::copy_data(&input) {
                    Ok(()) => {}
                    Err(e) => println!("[ERROR] {}", e),
                }

                println!("\nEnter another command (or 'quit' to exit):");
                let _ = stdout.flush();
            }
            Err(e) => {
                eprintln!("Error reading input: {}", e);
                break;
            }
        }
    }
}
