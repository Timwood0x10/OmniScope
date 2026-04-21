// C test: Multi-threaded patterns (simplified, no pthread dependency)
#include <stdlib.h>

struct ThreadData {
    int id;
    int value;
};

int compute(struct ThreadData* data) {
    return data->value * 2;
}

int main() {
    struct ThreadData data1 = {1, 100};
    struct ThreadData data2 = {2, 200};

    int result1 = compute(&data1);
    int result2 = compute(&data2);

    return result1 + result2;
}
