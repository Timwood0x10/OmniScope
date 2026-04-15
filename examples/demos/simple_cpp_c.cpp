// Simple C++ + C test
extern "C" {
    int c_execute_command(const char* command);
}

int main() {
    const char* cmd = "test";
    c_execute_command(cmd);
    return 0;
}