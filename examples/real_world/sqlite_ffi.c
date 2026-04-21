// Real-world FFI Test: SQLite C API Patterns
// Simplified version without external headers for testing

#include <stdlib.h>
#include <string.h>
#include <stdio.h>

// Mock SQLite types
typedef struct { char data[64]; } sqlite3;
typedef struct { char data[64]; } sqlite3_stmt;

// Mock functions simulating SQLite API
int sqlite3_open(const char *filename, sqlite3 **ppDb) {
    *ppDb = malloc(sizeof(sqlite3));
    return 0;
}
int sqlite3_close(sqlite3 *db) { free(db); return 0; }
int sqlite3_prepare_v2(sqlite3 *db, const char *sql, int nByte, sqlite3_stmt **ppStmt, const char **pzTail) {
    *ppStmt = malloc(sizeof(sqlite3_stmt));
    return 0;
}
int sqlite3_finalize(sqlite3_stmt *pStmt) { free(pStmt); return 0; }
void* sqlite3_malloc(int n) { return malloc(n); }
void sqlite3_free(void *ptr) { free(ptr); }
char* sqlite3_mprintf(const char *format, ...) { return strdup(format); }

// Issue: sqlite3_open requires sqlite3_close
sqlite3* open_database(const char *filename) {
    sqlite3 *db = NULL;
    int rc = sqlite3_open(filename, &db);
    if (rc != 0) {
        // Issue: db may still need to be closed
        return NULL;
    }
    // Missing: sqlite3_close will be needed
    return db;
}

// Issue: sqlite3_prepare_v2 requires sqlite3_finalize
int query_users(sqlite3 *db, const char *name) {
    sqlite3_stmt *stmt = NULL;
    const char *sql = "SELECT * FROM users WHERE name = ?";

    int rc = sqlite3_prepare_v2(db, sql, -1, &stmt, NULL);
    if (rc != 0) {
        return -1;
    }

    // Process...

    sqlite3_finalize(stmt);
    return 0;
}

// Issue: sqlite3_mprintf with missing sqlite3_free
char* build_query(const char *table, const char *where) {
    char *sql = sqlite3_mprintf("SELECT * FROM %s WHERE %s", table, where);
    // Issue: Caller must sqlite3_free(sql)
    return sql;
}

// Issue: Resource leak in error path
int process_query_with_leak(sqlite3 *db, const char *sql) {
    sqlite3_stmt *stmt1 = NULL;
    sqlite3_stmt *stmt2 = NULL;

    int rc = sqlite3_prepare_v2(db, sql, -1, &stmt1, NULL);
    if (rc != 0) return -1;

    rc = sqlite3_prepare_v2(db, sql, -1, &stmt2, NULL);
    if (rc != 0) {
        // Issue: stmt1 not finalized
        return -1;
    }

    // Process...

    sqlite3_finalize(stmt1);
    sqlite3_finalize(stmt2);
    return 0;
}

// Issue: Double free potential
void double_free_example(sqlite3 *db) {
    void *data = sqlite3_malloc(1024);
    if (!data) return;

    // Process data...

    sqlite3_free(data);

    // Issue: Double free
    sqlite3_free(data);
}

// Issue: Memory leak - allocated but never freed
void* allocate_and_forget(size_t size) {
    void *data = sqlite3_malloc(size);
    if (!data) return NULL;

    // Issue: Never freed
    return data;
}

// Correct pattern: proper cleanup
int correct_pattern(sqlite3 *db, const char *sql) {
    sqlite3_stmt *stmt = NULL;

    int rc = sqlite3_prepare_v2(db, sql, -1, &stmt, NULL);
    if (rc != 0) return -1;

    // Process...

    sqlite3_finalize(stmt);
    return 0;
}

// Issue: Use after free
int use_after_free_sqlite(sqlite3 *db) {
    void *data = sqlite3_malloc(100);
    if (!data) return -1;

    sqlite3_free(data);

    // Issue: Use after free
    memset(data, 0, 100);

    return 0;
}
