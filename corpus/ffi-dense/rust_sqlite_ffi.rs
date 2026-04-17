//! Rust SQLite FFI Binding Example
//! Demonstrates Rust → C FFI patterns with intentional bugs
//!
//! Expected issues:
//! 1. sqlite3_open without sqlite3_close (leak)
//! 2. sqlite3_prepare_v2 without sqlite3_finalize (leak)
//! 3. CString::into_raw without CString::from_raw (leak)
//! 4. Use after free via dangling pointer
//! 5. Null pointer dereference

use std::ffi::{CStr, CString};
use std::ptr;

// SQLite C function declarations
extern "C" {
    fn sqlite3_open(filename: *const i8, ppDb: *mut *mut std::ffi::c_void) -> i32;
    fn sqlite3_close(db: *mut std::ffi::c_void) -> i32;
    fn sqlite3_prepare_v2(
        db: *mut std::ffi::c_void,
        sql: *const i8,
        nByte: i32,
        ppStmt: *mut *mut std::ffi::c_void,
        pzTail: *mut *const i8,
    ) -> i32;
    fn sqlite3_step(stmt: *mut std::ffi::c_void) -> i32;
    fn sqlite3_finalize(stmt: *mut std::ffi::c_void) -> i32;
    fn sqlite3_column_text(stmt: *mut std::ffi::c_void, iCol: i32) -> *const i8;
    fn sqlite3_column_int(stmt: *mut std::ffi::c_void, iCol: i32) -> i32;
    fn sqlite3_bind_text(
        stmt: *mut std::ffi::c_void,
        index: i32,
        value: *const i8,
        n: i32,
        destructor: Option<unsafe extern "C" fn(*mut std::ffi::c_void)>,
    ) -> i32;
    fn sqlite3_exec(
        db: *mut std::ffi::c_void,
        sql: *const i8,
        callback: Option<unsafe extern "C" fn(*mut std::ffi::c_void, i32, *mut *mut i8, *mut *mut i8) -> i32>,
        arg: *mut std::ffi::c_void,
        errmsg: *mut *mut i8,
    ) -> i32;
    fn sqlite3_free(ptr: *mut std::ffi::c_void);
}

const SQLITE_OK: i32 = 0;
const SQLITE_ROW: i32 = 100;

// Bug 1: Resource leak - database not closed
pub fn leak_database(path: &str) -> Result<(), String> {
    let path_c = CString::new(path).map_err(|e| e.to_string())?;
    let mut db: *mut std::ffi::c_void = ptr::null_mut();
    
    unsafe {
        let rc = sqlite3_open(path_c.as_ptr(), &mut db);
        if rc != SQLITE_OK {
            // Bug: db should be closed even on error
            return Err("Failed to open database".to_string());
        }
        
        // Bug: sqlite3_close(db) never called
        // Missing: sqlite3_close(db);
    }
    
    Ok(())  // Leak: db never closed
}

// Bug 2: Statement leak - prepare without finalize
pub fn leak_statement(db: *mut std::ffi::c_void) -> Result<(), String> {
    let sql = CString::new("SELECT * FROM users").map_err(|e| e.to_string())?;
    let mut stmt: *mut std::ffi::c_void = ptr::null_mut();
    
    unsafe {
        let rc = sqlite3_prepare_v2(db, sql.as_ptr(), -1, &mut stmt, ptr::null_mut());
        if rc != SQLITE_OK {
            return Err("Failed to prepare statement".to_string());
        }
        
        sqlite3_step(stmt);
        
        // Bug: sqlite3_finalize(stmt) never called
        // Missing: sqlite3_finalize(stmt);
    }
    
    Ok(())  // Leak: stmt never finalized
}

// Bug 3: CString leak - into_raw without from_raw
pub fn leak_cstring(db: *mut std::ffi::c_void) -> Result<(), String> {
    let name = CString::new("test_user").map_err(|e| e.to_string())?;
    
    unsafe {
        let sql = CString::new("INSERT INTO users (name) VALUES (?)").map_err(|e| e.to_string())?;
        let mut stmt: *mut std::ffi::c_void = ptr::null_mut();
        
        sqlite3_prepare_v2(db, sql.as_ptr(), -1, &mut stmt, ptr::null_mut());
        
        // Bug: into_raw transfers ownership but we never reclaim it
        let raw = name.into_raw();
        sqlite3_bind_text(stmt, 1, raw, -1, None);
        
        // Missing: CString::from_raw(raw);
        
        sqlite3_finalize(stmt);
    }
    
    Ok(())  // Leak: CString memory leaked
}

// Bug 4: Use after free - dangling pointer
pub fn use_after_free(db: *mut std::ffi::c_void) -> Result<String, String> {
    let sql = CString::new("SELECT name FROM users LIMIT 1").map_err(|e| e.to_string())?;
    let mut stmt: *mut std::ffi::c_void = ptr::null_mut();
    
    unsafe {
        sqlite3_prepare_v2(db, sql.as_ptr(), -1, &mut stmt, ptr::null_mut());
        sqlite3_step(stmt);
        
        let name_ptr = sqlite3_column_text(stmt, 0);
        
        // Bug: Copying the pointer value, not the string
        // After finalize, this pointer is invalid
        let name = name_ptr;
        
        sqlite3_finalize(stmt);
        
        // Bug: Using dangling pointer
        let name_str = CStr::from_ptr(name).to_string_lossy().into_owned();
        
        Ok(name_str)  // Dangling pointer access!
    }
}

// Bug 5: Null pointer dereference
pub fn null_pointer_deref(db: *mut std::ffi::c_void) -> Result<i32, String> {
    let sql = CString::new("SELECT id FROM nonexistent_table").map_err(|e| e.to_string())?;
    let mut stmt: *mut std::ffi::c_void = ptr::null_mut();
    
    unsafe {
        // This will fail, stmt remains null
        let rc = sqlite3_prepare_v2(db, sql.as_ptr(), -1, &mut stmt, ptr::null_mut());
        
        if rc != SQLITE_OK {
            // Bug: Using stmt even though it's null
            let id = sqlite3_column_int(stmt, 0);  // Null pointer dereference!
            return Ok(id);
        }
        
        sqlite3_finalize(stmt);
    }
    
    Ok(0)
}

// Bug 6: Double close
pub fn double_close(db: *mut std::ffi::c_void) -> Result<(), String> {
    unsafe {
        sqlite3_close(db);
        sqlite3_close(db);  // Bug: Double close!
    }
    Ok(())
}

// Bug 7: SQL injection via format string
pub fn sql_injection(db: *mut std::ffi::c_void, user_input: &str) -> Result<(), String> {
    // Bug: String concatenation allows SQL injection
    let sql_str = format!("SELECT * FROM users WHERE name = '{}'", user_input);
    let sql = CString::new(sql_str).map_err(|e| e.to_string())?;
    
    unsafe {
        let mut errmsg: *mut i8 = ptr::null_mut();
        sqlite3_exec(db, sql.as_ptr(), None, ptr::null_mut(), &mut errmsg);
        
        if !errmsg.is_null() {
            sqlite3_free(errmsg as *mut std::ffi::c_void);
        }
    }
    
    Ok(())
}

// Correct pattern for reference
pub fn correct_usage(path: &str) -> Result<(), String> {
    let path_c = CString::new(path).map_err(|e| e.to_string())?;
    let mut db: *mut std::ffi::c_void = ptr::null_mut();
    
    unsafe {
        let rc = sqlite3_open(path_c.as_ptr(), &mut db);
        if rc != SQLITE_OK {
            if !db.is_null() {
                sqlite3_close(db);
            }
            return Err("Failed to open database".to_string());
        }
        
        let sql = CString::new("SELECT name FROM users LIMIT 1").map_err(|e| e.to_string())?;
        let mut stmt: *mut std::ffi::c_void = ptr::null_mut();
        
        let rc = sqlite3_prepare_v2(db, sql.as_ptr(), -1, &mut stmt, ptr::null_mut());
        if rc != SQLITE_OK {
            sqlite3_close(db);
            return Err("Failed to prepare".to_string());
        }
        
        if sqlite3_step(stmt) == SQLITE_ROW {
            let name_ptr = sqlite3_column_text(stmt, 0);
            if !name_ptr.is_null() {
                let name = CStr::from_ptr(name_ptr).to_string_lossy();
                println!("User: {}", name);
            }
        }
        
        sqlite3_finalize(stmt);
        sqlite3_close(db);
    }
    
    Ok(())
}

fn main() {
    println!("Rust SQLite FFI Example - Intentional Bugs");
    println!("==========================================");
    
    // Demonstrate the bugs
    match leak_database(":memory:") {
        Ok(_) => println!("leak_database: returned OK (but leaked!)"),
        Err(e) => println!("leak_database error: {}", e),
    }
    
    println!("\nNote: This code contains intentional bugs for testing OmniScope.");
    println!("Do not use in production!");
}
