// main.go - Go code calling C via cgo
//
// Demonstrates Go → C FFI boundary crossing.
// OmniScope should detect:
// 1. Ownership transfer across Go/C boundary
// 2. Dangerous C functions called from Go
// 3. Memory management issues

package main

/*
#cgo CFLAGS: -g -O0
#include "clib.h"
#include <stdlib.h>
*/
import "C"
import (
	"fmt"
	"unsafe"
)

// SafeFFICalls demonstrates safe FFI usage
func SafeFFICalls() {
	// Safe: no memory involved
	a := C.int(10)
	b := C.int(20)
	result := C.c_add(a, b)  // Go → C FFI boundary
	fmt.Printf("c_add(10, 20) = %d\n", result)

	result = C.c_multiply(a, b)  // Go → C FFI boundary
	fmt.Printf("c_multiply(10, 20) = %d\n", result)
}

// OwnershipTransfer demonstrates memory ownership across Go/C
func OwnershipTransfer() {
	// C allocates, Go uses, Go must free with C function
	size := C.size_t(1024)
	ptr := C.c_alloc(size)  // Line 38: C allocates, ownership to Go
	if ptr != nil {
		// Use the memory...
		C.c_free(ptr)  // Line 41: Go returns ownership to C
	}

	// String duplication
	goStr := "Hello from Go"
	cStr := C.CString(goStr)  // Go allocates C string
	defer C.free(unsafe.Pointer(cStr))  // Go frees

	dupStr := C.c_strdup(cStr)  // Line 48: C duplicates, ownership to Go
	if dupStr != nil {
		fmt.Printf("Duplicated: %s\n", C.GoString(dupStr))
		C.c_free_string(dupStr)  // Line 51: Go returns ownership
	}
}

// DangerousFFICalls demonstrates dangerous FFI usage
func DangerousFFICalls() {
	// VULNERABILITY: Buffer overflow
	dest := make([]byte, 10)
	src := "This string is way too long for the buffer"
	C.c_unsafe_copy((*C.char)(unsafe.Pointer(&dest[0])), C.CString(src))  // Line 60: HIGH risk

	// VULNERABILITY: Command injection
	cmd := "ls -la"
	ccmd := C.CString(cmd)
	defer C.free(unsafe.Pointer(ccmd))
	C.c_system_call(ccmd)  // Line 66: CRITICAL risk
}

func main() {
	fmt.Println("=== Go → C FFI Demo ===")

	SafeFFICalls()
	OwnershipTransfer()
	DangerousFFICalls()
}
