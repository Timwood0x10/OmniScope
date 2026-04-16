// Example Plugin for OmniScope
//
// This is a simple plugin that demonstrates how to extend OmniScope
// with custom analysis logic.

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// OmniScope Plugin ABI
// These structures and functions should match the ones defined in src/plugin/abi.zig

typedef struct {
    unsigned int abi_version;
    const char* name;
    const char* version;
    const char* description;
    int (*init)(void* ctx);
    void (*deinit)(void* ctx);
    int (*run)(void* ctx, const void* query, void* diag);
} LsPluginDescriptor;

typedef struct {
    void* fact_store;
    void* allocator;
    void* user_data;
} PluginContext;

typedef struct {
    unsigned char kind;
    unsigned int subject;
    unsigned int object;
    unsigned int context;
} LsFactQuery;

typedef struct {
    unsigned short kind;
    unsigned char severity;
    unsigned int loc;
    char* message;
    float confidence;
} LsDiagnostic;

typedef struct {
    void* context;
    void (*emit)(void* context, const LsDiagnostic* diag);
} LsDiagWriter;

// Simple user-defined check function
int checkForDangerousPattern(const char* func_name) {
    // Check for dangerous function names
    if (strstr(func_name, "system") != NULL) return 1;
    if (strstr(func_name, "exec") != NULL) return 1;
    if (strstr(func_name, "eval") != NULL) return 1;
    return 0;
}

// Plugin initialization
int plugin_init(void* ctx) {
    PluginContext* context = (PluginContext*)ctx;
    printf("Example Plugin initialized\n");
    return 0;
}

// Plugin cleanup
void plugin_deinit(void* ctx) {
    printf("Example Plugin deinitialized\n");
}

// Plugin run function
int plugin_run(void* ctx, const void* query, void* diag) {
    PluginContext* context = (PluginContext*)ctx;
    const LsFactQuery* q = (const LsFactQuery*)query;
    LsDiagWriter* writer = (LsDiagWriter*)diag;
    
    // Simple example: emit a diagnostic for dangerous patterns
    LsDiagnostic diagnostic = {
        .kind = 1,  // runtime_issue
        .severity = 2,  // warning
        .loc = 0,
        .message = (char*)"Example plugin: dangerous function detected",
        .confidence = 0.8f
    };
    
    writer->emit(writer->context, &diagnostic);
    
    return 0;
}

// Plugin descriptor (exported)
LsPluginDescriptor ls_plugin_descriptor = {
    .abi_version = 1,
    .name = "example_plugin",
    .version = "1.0.0",
    .description = "Example plugin that demonstrates the plugin system",
    .init = plugin_init,
    .deinit = plugin_deinit,
    .run = plugin_run
};

// Export function to get the descriptor
LsPluginDescriptor* ls_get_plugin_descriptor() {
    return &ls_plugin_descriptor;
}
