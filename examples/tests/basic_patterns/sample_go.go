// Go example - different memory model than C
package main

import (
	"fmt"
	"unsafe"
)

// Go uses garbage collection, but has unsafe pointer operations
func directAllocation() {
	// Go's GC handles this automatically
	s := make([]int, 100)
	_ = s
}

// Go pointers cannot be arithmetic, but can be converted
func pointerConversion() {
	var x int = 10
	xp := &x
	// In Go 1.17+, you can do pointer arithmetic with unsafe
	_ = unsafe.Pointer(xp)
}

// Interface with nil check
func nilInterface() interface{} {
	return nil
}

// Slice out of bounds (panic)
func sliceBounds() []int {
	s := []int{1, 2, 3}
	return s[0:10] // Will panic at runtime
}

// Map lookup with missing key
func mapLookup() {
	m := map[string]int{"a": 1}
	v, ok := m["b"] // ok is false
	_, _ = v, ok
}

func main() {
	directAllocation()
	pointerConversion()
	_ = nilInterface()
	// _ = sliceBounds() // Uncomment to see panic
	mapLookup()
	fmt.Println("Done")
}
