/**
 * Java → C (JNI) FFI Boundary Bugs
 *
 * Tests cross-language issues at the Java ↔ C boundary via JNI.
 * Java has GC + bounds checking; C has manual memory and raw pointers.
 * Bugs arise from JNI misuse, reference leaks, and type confusion.
 *
 * Uses JNI naming conventions (JNIenv, Java_ prefix) for detection.
 */

#include <stdlib.h>
#include <stdio.h>
#include <string.h>

/* Simulated JNI types */
typedef void* jobject;
typedef void* jstring;
typedef void* jarray;
typedef void* jbyteArray;
typedef int   jint;
typedef long  jlong;

typedef struct JNINativeInterface_* JNIEnv;

/* Simulated JNI functions */
extern jobject   NewGlobalRef(JNIEnv* env, jobject obj);
extern void      DeleteGlobalRef(JNIEnv* env, jobject ref);
extern jstring   NewStringUTF(JNIEnv* env, const char* str);
extern const char* GetStringUTFChars(JNIEnv* env, jstring str);
extern void      ReleaseStringUTFChars(JNIEnv* env, jstring str, const char* chars);
extern jbyteArray NewByteArray(JNIEnv* env, jint len);
extern void*     GetByteArrayElements(JNIEnv* env, jbyteArray arr);
extern void      ReleaseByteArrayElements(JNIEnv* env, jbyteArray arr, void* elems);
extern void*     GetPrimitiveArrayCritical(JNIEnv* env, jarray arr);
extern void      ReleasePrimitiveArrayCritical(JNIEnv* env, jarray arr, void* carray);

/* ============================================================
 * JNI-01: JNI GlobalRef leak (CWE-401)
 * C creates a JNI global reference but never deletes it.
 * Each call leaks one GlobalRef → eventual JNI table exhaustion.
 * Expected: resource_leak / jni_global_ref_leak
 * ============================================================ */
void jni_01_global_ref_leak(JNIEnv* env) {
    jobject local_obj = NULL; /* simulated local ref */
    jobject global = NewGlobalRef(env, local_obj);
    /* BUG: never calls DeleteGlobalRef(env, global) */
    printf("global ref at %p\n", global);
}

/* ============================================================
 * JNI-02: GetStringUTFChars without Release (CWE-401)
 * JNI string pinned in native memory, never released.
 * Expected: resource_leak / jni_string_leak
 * ============================================================ */
void jni_02_string_not_released(JNIEnv* env) {
    jstring jstr = NewStringUTF(env, "hello from Java");
    const char* native_str = GetStringUTFChars(env, jstr);
    printf("string: %s\n", native_str);
    /* BUG: never calls ReleaseStringUTFChars(env, jstr, native_str) */
}

/* ============================================================
 * JNI-03: Use after ReleaseStringUTFChars (CWE-416)
 * C continues using the native string pointer after releasing.
 * Expected: use_after_free
 * ============================================================ */
void jni_03_use_after_release(JNIEnv* env) {
    jstring jstr = NewStringUTF(env, "temporary");
    const char* native_str = GetStringUTFChars(env, jstr);
    char buf[64];
    strcpy(buf, native_str);

    ReleaseStringUTFChars(env, jstr, native_str);

    /* BUG: native_str is invalidated after release */
    printf("released: %s\n", native_str);  /* UAF */
}

/* ============================================================
 * JNI-04: GetPrimitiveArrayCritical + blocking JNI call (CWE-662)
 * GetPrimitiveArrayCritical pins the array and may block GC.
 * Making another JNI call while pinned causes deadlock/GC stall.
 * Expected: jni_deadlock / gc_block
 * ============================================================ */
void jni_04_critical_section_violation(JNIEnv* env) {
    jarray arr = NULL; /* simulated */
    void* pinned = GetPrimitiveArrayCritical(env, arr);

    /* BUG: making JNI call while array is pinned */
    jstring jstr = NewStringUTF(env, "this may deadlock");
    (void)jstr;

    ReleasePrimitiveArrayCritical(env, arr, pinned);
}

/* ============================================================
 * JNI-05: Wrong array type passed to JNI (CWE-704)
 * C casts a jbyteArray to jintArray and accesses with wrong stride.
 * Expected: type_confusion / buffer_overflow
 * ============================================================ */
void jni_05_type_confusion(JNIEnv* env) {
    jbyteArray byte_arr = NewByteArray(env, 16);
    /* BUG: treating byte array as int array — wrong element size */
    jint* int_view = (jint*)GetByteArrayElements(env, byte_arr);
    int_view[0] = 0xDEADBEEF;  /* writes 4 bytes into 1-byte slots */
    int_view[3] = 0xCAFEBABE;  /* out of bounds for byte array */
    ReleaseByteArrayElements(env, byte_arr, int_view);
}

/* ============================================================
 * JNI-06: C pointer passed to Java, Java stores it, C frees (CWE-416)
 * C allocates a struct, passes the pointer as jlong to Java.
 * Java stores it, C frees the memory → Java holds dangling pointer.
 * Expected: use_after_free / dangling_pointer
 * ============================================================ */
static void* g_c_struct_for_java = NULL;

void jni_06_init_struct(void) {
    g_c_struct_for_java = malloc(256);
    memset(g_c_struct_for_java, 0, 256);
}

jlong jni_06_get_handle(void) {
    return (jlong)(intptr_t)g_c_struct_for_java;
}

void jni_06_cleanup_struct(void) {
    free(g_c_struct_for_java);  /* BUG: Java still holds the jlong handle */
    g_c_struct_for_java = NULL;
}

void jni_06_use_handle(jlong handle) {
    /* BUG: if cleanup already ran, this is UAF */
    void* ptr = (void*)(intptr_t)handle;
    memset(ptr, 0xFF, 64);
}

/* ============================================================
 * JNI-07: Exception check missing after JNI call (CWE-252)
 * JNI calls can throw Java exceptions. C must check and handle.
 * Proceeding after an exception causes undefined behavior.
 * Expected: unchecked_exception / undefined_behavior
 * ============================================================ */
void jni_07_no_exception_check(JNIEnv* env) {
    jstring jstr = NewStringUTF(env, "test");
    const char* chars = GetStringUTFChars(env, jstr);
    /* BUG: no ExceptionCheck() — if NewStringUTF threw OOM, */
    /* chars is undefined and subsequent use is UB */
    char buf[32];
    strcpy(buf, chars);  /* may crash if exception pending */
    ReleaseStringUTFChars(env, jstr, chars);
}

/* ============================================================
 * JNI-08: Cross-language alloc/free mismatch (CWE-763)
 * Java allocates a byte array, C gets the elements pointer,
 * then C frees it with free() instead of ReleaseByteArrayElements.
 * Expected: cross_language_free
 * ============================================================ */
void jni_08_wrong_free(JNIEnv* env) {
    jbyteArray arr = NewByteArray(env, 256);
    void* elems = GetByteArrayElements(env, arr);
    memset(elems, 0, 256);
    /* BUG: using free() instead of ReleaseByteArrayElements */
    free(elems);  /* cross-language free mismatch */
}
