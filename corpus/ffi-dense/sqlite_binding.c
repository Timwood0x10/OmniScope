// SQLite FFI Binding Example
// Demonstrates common SQLite C API usage patterns with intentional bugs
//
// Expected issues:
// 1. sqlite3_open without sqlite3_close (leak)
// 2. sqlite3_prepare_v2 without sqlite3_finalize (leak)
// 3. sqlite3_bind_text with dangling pointer (use after free)
// 4. sqlite3_column_text result used after sqlite3_step (dangling pointer)
// 5. sqlite3_exec with unchecked return value

#include <sqlite3.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// Bug 1: Resource leak - sqlite3_open without sqlite3_close
int leak_database_open(const char* path) {
    sqlite3* db;
    int rc = sqlite3_open(path, &db);
    if (rc != SQLITE_OK) {
        // Missing: sqlite3_close(db);
        return -1;
    }
    // Missing: sqlite3_close(db);
    return 0;  // Leak: db never closed
}

// Bug 2: Statement leak - prepare without finalize
int leak_statement(sqlite3* db) {
    sqlite3_stmt* stmt;
    const char* sql = "SELECT * FROM users";
    int rc = sqlite3_prepare_v2(db, sql, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        return -1;
    }
    
    // Use the statement...
    sqlite3_step(stmt);
    
    // Missing: sqlite3_finalize(stmt);
    return 0;  // Leak: stmt never finalized
}

// Bug 3: Dangling pointer - bind text with freed string
int bind_dangling_pointer(sqlite3* db) {
    sqlite3_stmt* stmt;
    const char* sql = "INSERT INTO users (name) VALUES (?)";
    
    sqlite3_prepare_v2(db, sql, -1, &stmt, NULL);
    
    char* name = malloc(20);
    strcpy(name, "test_user");
    free(name);  // Free the string
    
    // Bug: binding freed memory
    sqlite3_bind_text(stmt, 1, name, -1, SQLITE_TRANSIENT);
    
    sqlite3_finalize(stmt);
    return 0;
}

// Bug 4: Use after finalize - column text after step
const char* get_user_name_dangling(sqlite3* db, int user_id) {
    sqlite3_stmt* stmt;
    const char* sql = "SELECT name FROM users WHERE id = ?";
    
    sqlite3_prepare_v2(db, sql, -1, &stmt, NULL);
    sqlite3_bind_int(stmt, 1, user_id);
    sqlite3_step(stmt);
    
    const char* name = (const char*)sqlite3_column_text(stmt, 0);
    
    // Bug: returning pointer that becomes invalid after finalize
    sqlite3_finalize(stmt);
    
    return name;  // Dangling pointer!
}

// Bug 5: Unchecked dangerous function
int dangerous_exec(sqlite3* db) {
    const char* sql = "DELETE FROM users";  // Dangerous: no WHERE clause
    
    // Bug: sqlite3_exec return value not checked
    sqlite3_exec(db, sql, NULL, NULL, NULL);
    
    return 0;
}

// Bug 6: SQL injection via string concatenation
int sql_injection(sqlite3* db, const char* user_input) {
    char sql[256];
    
    // Bug: sprintf with user input (format string + buffer overflow risk)
    sprintf(sql, "SELECT * FROM users WHERE name = '%s'", user_input);
    
    char* errmsg = NULL;
    sqlite3_exec(db, sql, NULL, NULL, &errmsg);
    
    if (errmsg) {
        sqlite3_free(errmsg);
    }
    
    return 0;
}

// Correct pattern for reference
int correct_usage(const char* path) {
    sqlite3* db;
    int rc = sqlite3_open(path, &db);
    if (rc != SQLITE_OK) {
        sqlite3_close(db);
        return -1;
    }
    
    sqlite3_stmt* stmt;
    const char* sql = "SELECT name FROM users LIMIT 1";
    rc = sqlite3_prepare_v2(db, sql, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        sqlite3_close(db);
        return -1;
    }
    
    if (sqlite3_step(stmt) == SQLITE_ROW) {
        const char* name = (const char*)sqlite3_column_text(stmt, 0);
        printf("User: %s\n", name);
    }
    
    sqlite3_finalize(stmt);
    sqlite3_close(db);
    return 0;
}

int main() {
    sqlite3* db;
    sqlite3_open(":memory:", &db);
    
    // Create test table
    sqlite3_exec(db, 
        "CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT)", 
        NULL, NULL, NULL);
    
    // Run buggy functions
    leak_database_open("test.db");
    leak_statement(db);
    bind_dangling_pointer(db);
    dangerous_exec(db);
    
    sqlite3_close(db);
    return 0;
}
