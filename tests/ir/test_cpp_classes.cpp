// C++ test: Classes and virtual functions
class Shape {
public:
    virtual int area() = 0;
    virtual ~Shape() {}
};

class Rectangle : public Shape {
private:
    int width, height;
public:
    Rectangle(int w, int h) : width(w), height(h) {}
    int area() override { return width * height; }
};

class Circle : public Shape {
private:
    int radius;
public:
    Circle(int r) : radius(r) {}
    int area() override { return 3 * radius * radius; }
};

int main() {
    Rectangle rect(5, 10);
    Circle circle(3);
    return rect.area() + circle.area();
}
