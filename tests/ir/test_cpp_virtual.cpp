// C++ test: Virtual functions and inheritance
#include <iostream>

class Base {
public:
    virtual int compute(int x) = 0;
    virtual ~Base() {}
};

class Derived1 : public Base {
public:
    int compute(int x) override {
        return x * 2;
    }
};

class Derived2 : public Base {
public:
    int compute(int x) override {
        return x * x;
    }
};

int process(Base* obj, int val) {
    return obj->compute(val);
}

int main() {
    Derived1 d1;
    Derived2 d2;
    int result = process(&d1, 5) + process(&d2, 5);
    return result;
}
