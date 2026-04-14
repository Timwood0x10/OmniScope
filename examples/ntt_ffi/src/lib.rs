// Rust FFI wrapper for C NTT library
// This demonstrates cross-language data flow analysis
// Rust bugs: unsafe pointer handling, FFI boundary crossing, data race

use std::ffi::{CStr, CString};
use std::fs::File;
use std::io::{BufRead, BufReader, Write};
use std::os::raw::{c_char, c_uint};
use std::path::Path;

// Import C functions via FFI
#[link(name = "ntt", kind = "static")]
#[link(name = "m")]
extern "C" {
    fn ntt_init(size: usize) -> i32;
    fn ntt_forward(input: *mut c_uint, size: usize) -> i32;
    fn ntt_inverse(input: *mut c_uint, size: usize) -> i32;
    fn ntt_get_state() -> *mut c_uint;
    fn ntt_finalize();
    fn poly_multiply(a: *mut c_uint, b: *mut c_uint, result: *mut c_uint, size: usize) -> i32;
    fn set_coefficients(coeffs: *mut c_uint, count: usize);
    fn debug_output(msg: *const c_char);
    fn create_from_user_input(data: *const c_char, len: usize);
    fn process_coefficients(filename: *const c_char);
}

/// Maximum polynomial size
const MAX_POLY_SIZE: usize = 4096;

/// Polynomial representation
pub struct Polynomial {
    pub coeffs: Vec<c_uint>,
    size: usize,
}

impl Polynomial {
    /// Create new polynomial with given size
    pub fn new(size: usize) -> Self {
        Polynomial {
            coeffs: vec![0; size],
            size,
        }
    }

    /// Set coefficient at index
    /// BUG: No bounds checking!
    pub fn set_coeff(&mut self, idx: usize, val: c_uint) {
        // BUG: idx could be >= self.size, causing buffer overflow
        self.coeffs[idx] = val;
    }

    /// Get coefficient at index
    /// BUG: Returns uninitialized value if idx >= size
    pub fn get_coeff(&self, idx: usize) -> c_uint {
        // BUG: No bounds check, reads beyond buffer
        self.coeffs[idx]
    }

    /// Initialize NTT context
    pub fn init_ntt(&self) -> Result<(), String> {
        let ret = unsafe { ntt_init(self.size) };
        if ret != 0 {
            return Err("NTT init failed".to_string());
        }
        Ok(())
    }

    /// Forward NTT transform
    /// BUG: Data race - multiple threads could access ntt_get_state simultaneously
    pub fn forward(&mut self) -> Result<(), String> {
        let ret = unsafe { ntt_forward(self.coeffs.as_mut_ptr(), self.size) };
        if ret != 0 {
            return Err("Forward NTT failed".to_string());
        }
        Ok(())
    }

    /// Get internal state pointer (DANGEROUS)
    /// BUG: use-after-free - pointer becomes invalid after ntt_finalize
    pub fn get_state_ptr(&self) -> *mut c_uint {
        unsafe { ntt_get_state() }
    }

    /// Multiply with another polynomial
    pub fn multiply(&self, other: &Polynomial) -> Result<Polynomial, String> {
        if self.size != other.size {
            return Err("Size mismatch".to_string());
        }

        let mut result = Polynomial::new(self.size);
        let ret = unsafe {
            poly_multiply(
                self.coeffs.as_mut_ptr(),
                other.coeffs.as_mut_ptr(),
                result.coeffs.as_mut_ptr(),
                self.size,
            )
        };

        if ret != 0 {
            return Err("Multiply failed".to_string());
        }
        Ok(result)
    }
}

impl Drop for Polynomial {
    fn drop(&mut self) {
        // BUG: Doesn't call ntt_finalize, leaving dangling pointers
    }
}

/// Process file and load coefficients (FFI boundary)
/// BUG: Command injection via filename
pub fn process_file(filename: &str) -> Result<(), String> {
    let c_filename = CString::new(filename).map_err(|e| e.to_string())?;
    unsafe {
        process_coefficients(c_filename.as_ptr());
    }
    Ok(())
}

/// Debug output via FFI
/// BUG: FFI boundary - data flows from Rust to C without validation
pub fn debug(msg: &str) {
    if let Ok(c_msg) = CString::new(msg) {
        unsafe {
            debug_output(c_msg.as_ptr());
        }
    }
}

/// Create coefficients from user input
/// BUG: Command injection possible via user_input
pub fn create_from_input(user_input: &str) {
    let c_input = CString::new(user_input).unwrap_or_default();
    unsafe {
        create_from_user_input(c_input.as_ptr(), user_input.len());
    }
}

/// Read coefficients from file
pub fn read_coeffs_from_file(path: &Path) -> Result<Polynomial, String> {
    let file = File::open(path).map_err(|e| e.to_string())?;
    let reader = BufReader::new(file);
    let mut coeffs = Vec::new();

    for line in reader.lines() {
        let line = line.map_err(|e| e.to_string())?;
        if let Ok(val) = line.trim().parse::<c_uint>() {
            coeffs.push(val);
        }
    }

    let mut poly = Polynomial::new(coeffs.len());
    poly.coeffs.copy_from_slice(&coeffs);
    Ok(poly)
}

/// Set coefficients with external data
/// BUG: FFI boundary crossing - data from external source flows into C
pub fn set_external_coeffs(data: &[c_uint]) {
    let mut owned = data.to_vec();
    unsafe {
        set_coefficients(owned.as_mut_ptr(), owned.len());
    }
    // BUG: owned is dropped here, but C still has pointer!
}

/// High-level wrapper for NTT multiplication
pub fn ntt_multiply(poly_a: &Polynomial, poly_b: &Polynomial) -> Result<Polynomial, String> {
    // Initialize NTT context
    poly_a.init_ntt()?;

    // Create copies for multiplication
    let mut a = poly_a.coeffs.clone();
    let mut b = poly_b.coeffs.clone();

    // Perform multiplication via FFI
    let mut result = Polynomial::new(poly_a.size);
    let ret = unsafe {
        poly_multiply(
            a.as_mut_ptr(),
            b.as_mut_ptr(),
            result.coeffs.as_mut_ptr(),
            poly_a.size,
        )
    };

    if ret != 0 {
        return Err("NTT multiply failed".to_string());
    }

    Ok(result)
}

/// User-controlled data path (security issue)
pub fn process_user_command(cmd: &str) {
    // BUG: Command injection - user input flows directly to system()
    debug(cmd);

    // BUG: Even worse - passes to C which also calls system()
    create_from_input(cmd);
}

/// Parse command line arguments and execute
pub fn run_cli(args: &[String]) -> Result<(), String> {
    if args.len() < 2 {
        return Err("Usage: ntt_cli <command> [args]".to_string());
    }

    match args[1].as_str() {
        "init" => {
            let size = if args.len() >= 3 {
                args[2].parse().unwrap_or(1024)
            } else {
                1024
            };
            let poly = Polynomial::new(size);
            poly.init_ntt()?;
            println!("NTT initialized with size {}", size);
        },
        "multiply" => {
            if args.len() < 4 {
                return Err("Usage: ntt_cli multiply <file1> <file2>".to_string());
            }
            let poly1 = read_coeffs_from_file(Path::new(&args[2]))?;
            let poly2 = read_coeffs_from_file(Path::new(&args[3]))?;
            let result = poly1.multiply(&poly2)?;
            println!("Multiplication complete");
        },
        "debug" => {
            if args.len() >= 3 {
                debug(&args[2]);  // BUG: command injection
            }
        },
        "user" => {
            if args.len() >= 3 {
                process_user_command(&args[2]);  // BUG: command injection
            }
        },
        "cleanup" => {
            unsafe { ntt_finalize() };
            // BUG: Now ntt_get_state() returns freed pointer
            let state = unsafe { ntt_get_state() };
            if !state.is_null() {
                println!("State after cleanup: {}", unsafe { *state });
                // BUG: Use-after-free!
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
    fn test_polynomial_creation() {
        let poly = Polynomial::new(1024);
        assert_eq!(poly.size, 1024);
        assert_eq!(poly.coeffs.len(), 1024);
    }

    #[test]
    fn test_set_get_coeff() {
        let mut poly = Polynomial::new(1024);
        poly.set_coeff(0, 42);
        poly.set_coeff(100, 100);
        assert_eq!(poly.get_coeff(0), 42);
        assert_eq!(poly.get_coeff(100), 100);
    }

    #[test]
    fn test_ntt_init() {
        let poly = Polynomial::new(1024);
        assert!(poly.init_ntt().is_ok());
    }
}