/*
 * Medium Test: Network FFI Patterns
 * Expected Issues: 8
 * - 2 leak (socket without close)
 * - 2 use_after_free
 * - 1 buffer_overflow
 * - 1 format_string
 * - 1 command_injection
 * - 1 unchecked_return
 */

#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>

// Issue 1: leak - socket without close
int create_socket_leak(void) {
    int sockfd = socket(AF_INET, SOCK_STREAM, 0);
    if (sockfd < 0) return -1;
    // Socket not closed on success path
    return sockfd;
}

// Issue 2: leak - accept without close
int accept_connection_leak(int server_fd) {
    struct sockaddr_in client_addr;
    socklen_t addr_len = sizeof(client_addr);
    int client_fd = accept(server_fd, (struct sockaddr*)&client_addr, &addr_len);
    if (client_fd < 0) return -1;
    // Client socket not closed
    return client_fd;
}

// Issue 3: use_after_free
char* read_and_free(int fd) {
    char* buffer = (char*)malloc(1024);
    if (buffer == NULL) return NULL;
    
    ssize_t bytes = read(fd, buffer, 1024);
    if (bytes < 0) {
        free(buffer);
        return NULL;
    }
    
    char* result = strdup(buffer);
    free(buffer);
    // Potential use after free if strdup failed
    return result;
}

// Issue 4: use_after_free in error path
int process_data(char* data) {
    if (data == NULL) return -1;
    
    int result = strlen(data);
    free(data);
    
    // Log after free
    printf("Processed %d bytes: %s\n", result, data);
    return result;
}

// Issue 5: buffer_overflow
void copy_address(char* dest, const char* src) {
    strcpy(dest, src);  // No bounds check
}

// Issue 6: format_string
void log_connection(const char* client_ip, const char* user_input) {
    char log_buffer[512];
    sprintf(log_buffer, "Connection from %s: ", client_ip);
    strcat(log_buffer, user_input);  // Potential overflow
    printf(log_buffer);  // Format string
}

// Issue 7: command_injection
int execute_user_command(const char* user_cmd) {
    char command[256];
    sprintf(command, "ls %s", user_cmd);  // Command injection
    return system(command);
}

// Issue 8: unchecked_return
void send_data_unchecked(int fd, const char* data) {
    send(fd, data, strlen(data), 0);  // Return not checked
}

// Safe example
int safe_send_data(int fd, const char* data, size_t len) {
    if (data == NULL || len == 0) return -1;
    
    size_t sent = 0;
    while (sent < len) {
        ssize_t result = send(fd, data + sent, len - sent, 0);
        if (result < 0) return -1;
        sent += (size_t)result;
    }
    return 0;
}

// Safe socket handling
int safe_socket_example(void) {
    int sockfd = socket(AF_INET, SOCK_STREAM, 0);
    if (sockfd < 0) return -1;
    
    struct sockaddr_in addr = {
        .sin_family = AF_INET,
        .sin_port = htons(8080),
        .sin_addr.s_addr = INADDR_ANY,
    };
    
    if (bind(sockfd, (struct sockaddr*)&addr, sizeof(addr)) < 0) {
        close(sockfd);
        return -1;
    }
    
    close(sockfd);
    return 0;
}
