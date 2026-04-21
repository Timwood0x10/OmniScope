/*
 * Go FFI Simple Test
 * Tests real Go→C FFI patterns (cgo) for unsafe boundary analysis
 *
 * Expected Issues: 3
 * - C.CString without C.free (ownership leak)
 * - C.malloc without C.free (ownership leak)
 * - Go GC doesn't manage C memory
 */

package main

/*
#cgo CFLAGS: -I.
#cgo LDFLAGS: -L.
#include <stdlib.h>
#include <string.h>

void c_process_string(char* ptr);
void c_free_string(char* ptr);
*/
import "C"
import "unsafe"

// Test 1: C.CString without C.free - ownership leak
func CStringLeak() *C.char {
	str := "hello"
	cstr := C.CString(str) // Go allocates C memory
	// Leak: never calls C.free(cstr)
	return cstr
}

// Test 2: C.malloc without C.free - ownership leak
func CMallocLeak() unsafe.Pointer {
	ptr := C.malloc(100) // C allocates memory
	// Leak: never calls C.free(ptr)
	return ptr
}

// Test 3: C.CBytes without C.free - ownership leak
func CBytesLeak() unsafe.Pointer {
	data := []byte{1, 2, 3, 4, 5}
	cbytes := C.CBytes(data) // Go allocates C memory
	// Leak: never calls C.free(cbytes)
	return cbytes
}

// Test 4: Correct pattern - C.CString + C.free
func CorrectCString() {
	str := "hello"
	cstr := C.CString(str)
	C.c_process_string(cstr)
	C.free(unsafe.Pointer(cstr)) // Correct: C.free
}

// Test 5: Correct pattern - C.malloc + C.free
func CorrectCMalloc() {
	ptr := C.malloc(100)
	if ptr != nil {
		C.free(ptr) // Correct: C.free
	}
}

func main() {
	CStringLeak()
	CMallocLeak()
	CBytesLeak()
	CorrectCString()
	CorrectCMalloc()
}
