// Simple C library
#include <stdlib.h>
#include <string.h>

int c_execute_command(const char* command) {
    char cmd[256];
    strcpy(cmd, command);
    return system(cmd);
}