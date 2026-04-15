// Cross-language test case for OmniScope
// Tests: source (read) -> propagation -> sink (system)

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

// Source function - reads data from stdin
char* get_input() {
    char* buffer = malloc(128);
    fgets(buffer, 128, stdin);
    return buffer;
}

// Internal helper - processes data
void process_data(char* data) {
    printf("Processing: %s\n", data);
}

// Another internal function - passes data along
char* transform(char* input) {
    char* result = malloc(128);
    snprintf(result, 128, "transformed: %s", input);
    return result;
}

// Sink function - executes system command
int execute_command(char* cmd) {
    return system(cmd);
}

// Entry point with vulnerable data flow: read -> system
int main(int argc, char* argv[]) {
    char* input = get_input();       // SOURCE: tainted data from user
    process_data(input);

    char* transformed = transform(input);

    execute_command(transformed);     // SINK: executes tainted command
    return 0;
}