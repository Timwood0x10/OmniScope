/**
 * ╔══════════════════════════════════════════════════════════════╗
 * ║  OmniScope v0.1.7 — Java JNI Detection Test Cases               ║
 * ║  Target: A3 — Java_* prefix / JNI_* patterns / JVM_* exclusion   ║
 * ╚══════════════════════════════════════════════════════════════╝
 *
 * Intentional bugs: 6
 * Control cases: 2
 *
 * Patterns tested:
 *   - Java_com_example_* (JNI native method naming convention)
 *   - JNI_OnLoad / JNI_FindClass / JNI_GetMethodID (standard JNI API)
 *   - CallVoidMethod / NewObject / GetStringUTFChars (JNI method patterns)
 *   - JVM_* exclusion (should NOT be classified as .java — was .c before fix)
 */

#include <jni.h>
#include <stdlib.h>
#include <string.h>

// ================================================================
// BUG-JNI-01: Java_com_example_MyClass_nativeLeak — memory leak in native method
//
// Standard JNI function name pattern: Java_<package>_<class>_<method>
// Allocates memory via JNI but never releases it.
// ================================================================

JNIEXPORT void JNICALL
Java_com_example_MyClass_nativeLeak(JNIEnv* env, jobject thiz) {
    // Allocate C memory that's never freed — leaks across JNI boundary
    char* leaked = (char*)malloc(4096);
    memset(leaked, 'A', 4096);

    // Store it as a global reference so GC can't reclaim
    jclass cls = (*env)->GetObjectClass(env, thiz);
    jfieldID fid = (*env)->GetFieldID(env, cls, "nativePtr", "J");
    (*env)->SetLongField(env, thiz, fid, (jlong)(uintptr_t)leaked);
    // BUG: leaked is never freed — cross-language leak

    (void)cls; (void)fid; // Suppress warnings
}

// ================================================================
// BUG-JNI-02: JNI_OnLoad with dangling callback registration
//
// JNI_OnLoad is called when the library is loaded. Registering a
// callback here that captures stack data creates an escape path.
// ================================================================

static void (*g_jni_callback)(void*) = NULL;
static char* g_callback_data = NULL;

JNIEXPORT jint JNICALL
JNI_OnLoad(JavaVM* vm, void* reserved) {
    JNIEnv* env = NULL;
    (*vm)->GetEnv(vm, (void**)&env, JNI_VERSION_1_8);

    // Allocate data during library init
    g_callback_data = (char*)malloc(256);
    strcpy(g_callback_data, "JNI_INIT_DATA");

    // Register callback — indirect escape through function pointer
    // E2-2c: This alias chain reaches FFI → severity boost expected
    g_jni_callback = &jni_onDataCallback;

    (void)reserved;
    return JNI_VERSION_1_8;
}

static void jni_onDataCallback(void* data) {
    // Callback fires asynchronously — data may be invalid
    printf("Callback data: %s\n", (char*)data); // Potential UAF
}

// ================================================================
// BUG-JNI-03: JNI_GetStringUTFChars without ReleaseStringUTFChars
//
// Classic JNI anti-pattern: get a string copy from Java,
// forget to release it. Leaks the internal copy.
// ================================================================

JNIEXPORT jstring JNICALL
Java_com_example_Utils_toUpperCase(JNIEnv* env, jclass cls, jstring input) {
    const char* str = (*env)->GetStringUTFChars(env, input, NULL);
    if (!str) return NULL;

    // Convert to uppercase
    size_t len = strlen(str);
    char* upper = (char*)malloc(len + 1);
    for (size_t i = 0; i < len; i++) {
        upper[i] = (str[i] >= 'a' && str[i] <= 'z') ? str[i] - 32 : str[i];
    }
    upper[len] = '\0';

    jstring result = (*env)->NewStringUTF(env, upper);

    // BUG: Forgot (*env)->ReleaseStringUTFChars(env, input, str)!
    free(upper);

    (void)cls;
    return result;
}

// ================================================================
// BUG-JNI-04: JNI_NewObject + JNI_CallVoidMethod on freed object
//
// Create a Java object via JNI, then call methods after it's been
// potentially garbage collected or invalidated.
// ================================================================

JNIEXPORT void JNICALL
Java_com_example_Factory_createAndUseObject(JNIEnv* env, jclass cls) {
    // Find class and constructor
    jclass target_cls = (*env)->FindClass(env, "com/example/Target");
    jmethodID ctor = (*env)->GetMethodID(env, target_cls, "<init>", "()V");
    jmethodID process = (*env)->GetMethodID(env, target_cls, "process", "()V");

    // Create instance
    jobject obj = (*env)->NewObject(env, target_cls, ctor);

    // ... complex logic that may trigger GC ...

    (*env)->CallVoidMethod(env, obj, process);
    // BUG: obj may have been moved by GC — potential UAF
    // Also: no DeleteLocalRef for target_cls, ctor, process

    (void)cls;
}

// ================================================================
// BUG-JNI-05: GetArrayElements without ReleaseArrayElements
//
// Get direct pointer to Java array contents. If not released,
// the GC can't move/pin the array properly.
// ================================================================

JNIEXPORT jint JNICALL
Java_com_example_ArrayOps_sumArray(JNIEnv* env, jclass cls, jintArray arr) {
    jsize len = (*env)->GetArrayLength(env, arr);
    jint* elements = (*env)->GetIntArrayElements(env, arr, NULL);
    if (!elements) return 0;

    jint sum = 0;
    for (jsize i = 0; i < len; i++) {
        sum += elements[i];
    }

    // BUG: Forgot (*env)->ReleaseIntArrayElements(env, arr, elements, 0)!
    // Array is pinned forever → memory pressure, potential crash

    (void)cls;
    return sum;
}

// ================================================================
// BUG-JNI-06: Cross-thread JNI access without AttachCurrentThread
//
// Accessing JNIEnv from a thread that didn't attach to the VM.
// The env pointer may be stale or invalid.
// ================================================================

static pthread_t g_worker_thread;
static JavaVM* g_cached_vm = NULL;

JNIEXPORT void JNICALL
Java_com_example_ThreadBridge_startWorker(JNIEnv* env, jclass cls) {
    (*env)->GetJavaVM(env, &g_cached_vm);

    // Start worker thread that will use cached VM pointer unsafely
    pthread_create(&g_worker_thread, NULL, worker_main, NULL);

    (void)cls;
}

static void* worker_main(void* arg) {
    // BUG: Using g_cached_vm without AttachCurrentThread!
    // The JNIEnv obtained this way may be invalid.
    JNIEnv* unsafe_env = NULL;
    // Missing: (*g_cached_vm)->AttachCurrentThread(g_cached_vm, (void**)&unsafe_env, NULL)
    // This would cause SIGSEGV when using unsafe_env

    (void)arg;
    (void)unsafe_env;
    return NULL;
}

// ================================================================
// CONTROL-JNI-01: Correct JNI pattern — paired Get/Release
// ================================================================

JNIEXPORT jstring JNICALL
Java_com_example_Utils_safeToString(JNIEnv* env, jclass cls, jstring input) {
    const char* str = (*env)->GetStringUTFChars(env, input, NULL);
    if (!str) return NULL;

    jstring result = (*env)->NewStringUTF(env, str);

    // Correct: always release
    (*env)->ReleaseStringUTFChars(env, input, str);

    (void)cls;
    return result;
}

// ================================================================
// CONTROL-JNI-02: JVM_* functions are NOT user JNI calls
//
// These are JVM internal functions. They should be classified as
// .unknown (NOT .java). Before v0.1.7 fix, they were incorrectly
// classified as .c due to dead-code exclusion bug.
// ================================================================

// Simulated JVM internal functions (these exist in real JVM implementations)
// They should NOT trigger Java/JNI detection
void JVM_GetSystemClassLoader(void) { /* Internal — not user code */ }
void JVM_FindClassFromBootLoader(const char* name) { /* Internal */ }
jint JVM_IsSameObject(void* a, void* b) { /* Internal */ return 0; }

// A helper that uses JVM_* functions — should NOT be flagged as FFI issue
void safe_jvm_internal_helper() {
    JVM_GetSystemClassLoader();      // Should be .unknown (not .java/.c)
    JVM_FindClassFromBootLoader("X"); // Should be .unknown
    JVM_IsSameObject(NULL, NULL);     // Should be .unknown
}
