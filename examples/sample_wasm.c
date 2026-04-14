// Minimal C for WASM - no stdlib
int add(int a, int b) {
    return a + b;
}

int fibonacci(int n) {
    if (n <= 1) return n;
    return fibonacci(n - 1) + fibonacci(n - 2);
}

void main(void) {
    int x = add(1, 2);
    int f = fibonacci(10);
    (void)x;
    (void)f;
}
