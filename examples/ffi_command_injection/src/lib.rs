// Blockchain Transaction Parser - Rust FFI Layer
//
// Simulates a Rust blockchain validator that receives user transaction hashes
// and verifies them using a high-performance C crypto library.
//
// VULNERABILITY FLOW:
// 1. Attacker sends malicious transaction hash via CLI/API
// 2. Rust validates hash format but NOT content
// 3. Hash is passed to C via FFI
// 4. C library uses hash in system() command - COMMAND INJECTION!
//
// Real-world parallel: Solana, Aptos, Sui validators that call
// OpenSSL/BoringSSL via FFI for cryptographic operations.

use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::process::Command;

// Import C crypto library functions
#[link(name = "crypto_lib", kind = "static")]
#[link(name = "m")]
extern "C" {
    fn crypto_init() -> i32;
    fn register_transaction(tx_hash: *const c_char, sender: *const c_char, 
                           receiver: *const c_char, amount: i32) -> i32;
    fn verify_transaction(tx_hash: *const c_char) -> i32;
    fn debug_dump_transaction(tx_hash: *const c_char) -> i32;
    fn batch_verify(hashes: *const *const c_char, count: i32) -> i32;
    fn crypto_cleanup();
}

/// Transaction hash format validator
/// Checks format only, NOT content - this is the security hole!
fn validate_hash_format(hash: &str) -> Result<(), String> {
    // Rust validates FORMAT (length, characters)
    if hash.len() != 64 {
        return Err("Hash must be 64 characters".to_string());
    }
    
    if !hash.chars().all(|c| c.is_ascii_hexdigit()) {
        return Err("Hash must be hexadecimal".to_string());
    }
    
    // BUG: Rust thinks the hash is safe because format is valid!
    // But attacker can inject: "aaa...; rm -rf /; #"
    // This passes Rust validation but causes command injection in C
    
    Ok(())
}

/// Verify a single transaction hash
/// BUG: Command injection via hash parameter
pub fn verify_tx_hash(hash: &str) -> Result<bool, String> {
    // Rust validation - only checks format
    validate_hash_format(hash)?;
    
    // Convert to C string
    let c_hash = CString::new(hash).map_err(|e| e.to_string())?;
    
    // Call C library - BUG: hash is not sanitized in C!
    unsafe {
        let result = verify_transaction(c_hash.as_ptr());
        Ok(result == 0)
    }
}

/// Verify multiple transaction hashes in batch
pub fn batch_verify_hashes(hashes: &[String]) -> Result<Vec<bool>, String> {
    // Validate all hashes first (Rust-side validation)
    for hash in hashes {
        validate_hash_format(hash)?;
    }
    
    // Convert to C strings
    let c_hashes: Vec<CString> = hashes
        .iter()
        .map(|h| CString::new(h.as_str()).unwrap())
        .collect();
    
    let c_hash_ptrs: Vec<*const c_char> = c_hashes
        .iter()
        .map(|cs| cs.as_ptr())
        .collect();
    
    // Call C batch verify
    unsafe {
        let result = batch_verify(c_hash_ptrs.as_ptr(), hashes.len() as i32);
        
        // Return vector indicating success/failure for each
        let mut results = Vec::with_capacity(hashes.len());
        for i in 0..hashes.len() {
            results.push((i as i32) < result);
        }
        Ok(results)
    }
}

/// Debug dump transaction by hash
/// BUG: Format string vulnerability via FFI
pub fn debug_tx(hash: &str) -> Result<(), String> {
    validate_hash_format(hash)?;
    
    let c_hash = CString::new(hash).map_err(|e| e.to_string())?;
    
    unsafe {
        let result = debug_dump_transaction(c_hash.as_ptr());
        if result != 0 {
            return Err("Transaction not found".to_string());
        }
    }
    
    Ok(())
}

/// Register a new transaction
pub fn register_tx(hash: &str, sender: &str, receiver: &str, amount: i32) -> Result<(), String> {
    validate_hash_format(hash)?;
    
    let c_hash = CString::new(hash).map_err(|e| e.to_string())?;
    let c_sender = CString::new(sender).map_err(|e| e.to_string())?;
    let c_receiver = CString::new(receiver).map_err(|e| e.to_string())?;
    
    unsafe {
        let result = register_transaction(
            c_hash.as_ptr(),
            c_sender.as_ptr(),
            c_receiver.as_ptr(),
            amount,
        );
        
        if result != 0 {
            return Err("Failed to register transaction".to_string());
        }
    }
    
    Ok(())
}

/// CLI interface for transaction verification
pub fn run_cli(args: &[String]) -> Result<(), String> {
    if args.len() < 2 {
        println!("Blockchain Transaction Verifier");
        println!("Usage: {} <command> [args]", args[0]);
        println!("Commands:");
        println!("  verify <hash>     - Verify a transaction hash");
        println!("  register <hash> <sender> <receiver> <amount>");
        println!("  debug <hash>      - Debug dump transaction");
        return Ok(());
    }
    
    match args[1].as_str() {
        "verify" => {
            if args.len() < 3 {
                return Err("Usage: verify <hash>".to_string());
            }
            
            let hash = &args[2];
            println!("[Rust] Verifying hash: {}", hash);
            
            // This is where the vulnerability is triggered!
            // Attacker can inject: "aaa...aaa; cat /etc/passwd; #"
            match verify_tx_hash(hash) {
                Ok(true) => println!("[Rust] Transaction verified ✓"),
                Ok(false) => println!("[Rust] Transaction not found"),
                Err(e) => println!("[Rust] Error: {}", e),
            }
        },
        
        "register" => {
            if args.len() < 6 {
                return Err("Usage: register <hash> <sender> <receiver> <amount>".to_string());
            }
            
            let hash = &args[2];
            let sender = &args[3];
            let receiver = &args[4];
            let amount: i32 = args[5].parse().unwrap_or(0);
            
            match register_tx(hash, sender, receiver, amount) {
                Ok(()) => println!("[Rust] Transaction registered ✓"),
                Err(e) => println!("[Rust] Error: {}", e),
            }
        },
        
        "debug" => {
            if args.len() < 3 {
                return Err("Usage: debug <hash>".to_string());
            }
            
            let hash = &args[2];
            println!("[Rust] Debug dump for: {}", hash);
            
            if let Err(e) = debug_tx(hash) {
                println!("[Rust] Error: {}", e);
            }
        },
        
        _ => {
            return Err(format!("Unknown command: {}", args[1]));
        }
    }
    
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_valid_hash() {
        let valid_hash = "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2";
        assert!(validate_hash_format(valid_hash).is_ok());
    }

    #[test]
    fn test_invalid_length() {
        let short_hash = "a1b2c3";
        assert!(validate_hash_format(short_hash).is_err());
    }

    #[test]
    fn test_non_hex() {
        let non_hex = "zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz";
        assert!(validate_hash_format(non_hex).is_err());
    }
}