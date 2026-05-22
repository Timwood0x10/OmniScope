/**
 * OmniScope Red Team — JNI (Java Native Interface) Bug Test Cases
 *
 * Simulates bugs that occur at Java ↔ Native (C/C++) FFI boundaries.
 * Based on patterns from JDK_IR_SPEC.md:
 *   - JNI local/global reference lifecycle errors
 *   - Critical JNI violations
 *   - JNI type safety violations
 *   - Array pinning issues
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* Simulated JNI types */
typedef void* jobject;
typedef void* jclass;
typedef void* jstring;
typedef void* jarray;
typedef void* jintArray;
typedef void* jbyteArray;
typedef void* JNIEnv;
typedef int jint;
typedef long jlong;
typedef char jboolean;

#define JNI_OK 0
#define JNI_ERR (-1)
#define JNI_FALSE 0
#define JNI_TRUE 1

/* Simulated JNI functions */
static jobject (*NewGlobalRef)(JNIEnv *env, jobject obj);
static void (*DeleteGlobalRef)(JNIEnv *env, jobject globalRef);
static void (*DeleteLocalRef)(JNIEnv *env, jobject localRef);
static jstring (*NewStringUTF)(JNIEnv *env, const char *utf);
static const char* (*GetStringUTFChars)(JNIEnv *env, jstring str, jboolean *isCopy);
static void (*ReleaseStringUTFChars)(JNIEnv *env, jstring str, const char *chars);
static jintArray (*NewIntArray)(JNIEnv *env, jint len);
static jint* (*GetIntArrayElements)(JNIEnv *env, jintArray arr, jboolean *isCopy);
static void (*ReleaseIntArrayElements)(JNIEnv *env, jintArray arr, jint *elems, jint mode);
static void (*ExceptionCheck)(JNIEnv *env);

/* Simulated JNI env for testing */
static JNIEnv g_env;

/* ================================================================
 * JNI-BUG-01: Local reference used after frame pop
 *
 * JNI local references are only valid within the current native
 * method call or between PushLocalFrame/PopLocalFrame.
 * Using a local reference after PopLocalFrame is undefined.
 *
 * Expected: use_after_free (CWE-416)
 * ================================================================ */
void jni_bug_01_local_ref_after_pop(void) {
    jobject local_obj = NULL;

    /* Simulate PushLocalFrame */
    local_obj = malloc(64);  /* Simulates NewLocalRef */
    if (!local_obj) return;

    /* Use local reference */
    printf("JNI-BUG-01: local ref = %p\n", local_obj);

    /* Simulate PopLocalFrame — local refs are invalidated */
    /* In real JNI: PopLocalFrame(env, NULL); */
    free(local_obj);

    /* [BUG] Use local reference after frame pop */
    printf("JNI-BUG-01: after pop = %p\n", local_obj);  /* UAF */
}

/* ================================================================
 * JNI-BUG-02: Global reference leak
 *
 * Create a global reference but never delete it.
 * Global references persist until explicitly deleted.
 *
 * Expected: memory_leak (CWE-401)
 * ================================================================ */
static jobject g_leaked_global = NULL;

void jni_bug_02_global_ref_leak(void) {
    jobject local = malloc(128);  /* Simulates JNI object creation */

    /* Create global reference */
    g_leaked_global = local;  /* Simulates NewGlobalRef */

    /* [BUG] Never calls DeleteGlobalRef — leak */
    /* Should have: DeleteGlobalRef(env, g_leaked_global); */

    printf("JNI-BUG-02: global ref created = %p\n", g_leaked_global);
}

/* ================================================================
 * JNI-BUG-03: GetStringUTFChars without Release
 *
 * GetStringUTFChars pins a string. Must call ReleaseStringUTFChars.
 * Forgetting to release causes memory leak and potential GC block.
 *
 * Expected: memory_leak (CWE-401)
 * ================================================================ */
void jni_bug_03_string_not_released(void) {
    char *str = (char*)malloc(64);  /* Simulates GetStringUTFChars */
    strcpy(str, "JNI string data");

    /* Use the string */
    printf("JNI-BUG-03: %s\n", str);

    /* [BUG] Forgot ReleaseStringUTFChars */
    /* Should have: ReleaseStringUTFChars(env, jstr, str); */
    /* String remains pinned, GC cannot collect the Java object */

    free(str);  /* Only frees native copy, doesn't release JNI pin */
}

/* ================================================================
 * JNI-BUG-04: GetIntArrayElements without Release
 *
 * Array elements are pinned in JVM heap. Not releasing blocks
 * GC compaction.
 *
 * Expected: memory_leak / resource_leak
 * ================================================================ */
void jni_bug_04_array_not_released(void) {
    int *elems = (int*)malloc(sizeof(int) * 100);  /* Simulates GetIntArrayElements */
    if (!elems) return;

    for (int i = 0; i < 100; i++) {
        elems[i] = i * 2;
    }

    printf("JNI-BUG-04: elems[50] = %d\n", elems[50]);

    /* [BUG] Forgot ReleaseIntArrayElements */
    /* Array remains pinned in JVM heap */
    free(elems);
}

/* ================================================================
 * JNI-BUG-05: Using stale reference after exception
 *
 * After a JNI exception, pending exceptions invalidate most
 * JNI calls. Continuing to use references is undefined.
 *
 * Expected: use_after_free / null_dereference
 * ================================================================ */
void jni_bug_05_stale_ref_after_exception(void) {
    jobject obj = malloc(64);  /* Simulates JNI call */

    /* Simulate: JNI call throws exception */
    int exception_occurred = 1;  /* ExceptionCheck returns true */

    if (exception_occurred) {
        /* [BUG] Should return immediately or handle exception.
         * Using obj after exception is undefined. */
        printf("JNI-BUG-05: using ref after exception = %p\n", obj);
        free(obj);
        return;
    }

    free(obj);
}

/* ================================================================
 * JNI-BUG-06: Critical JNI with Java object access
 *
 * GetCriticalStringUTFChars / GetPrimitiveArrayCritical restrict
 * what native code can do (no JNI calls, no GC allocation).
 * Violating these restrictions causes deadlocks or crashes.
 *
 * Expected: thread_safety / deadlock
 * ================================================================ */
void jni_bug_06_critical_jni_violation(void) {
    int *critical = (int*)malloc(sizeof(int) * 50);  /* Simulates GetPrimitiveArrayCritical */

    /* Inside critical region: must NOT call JNI functions */
    for (int i = 0; i < 50; i++) {
        critical[i] = i;
    }

    /* [BUG] Calling JNI function inside critical region!
     * In real JNI: env->NewObject(...) would deadlock */
    jobject new_obj = malloc(32);  /* Simulates JNI allocation inside critical */
    free(new_obj);

    /* Release critical */
    free(critical);
}

/* ================================================================
 * JNI-BUG-07: JNI function called from wrong thread
 *
 * JNIEnv is thread-local. Using another thread's JNIEnv
 * causes undefined behavior.
 *
 * Expected: thread_safety
 * ================================================================ */
static JNIEnv *g_other_thread_env = NULL;

void jni_bug_07_wrong_thread_env(void) {
    /* Simulate: captured env from another thread */
    JNIEnv *wrong_env = &g_env;  /* Simulates cross-thread env capture */

    /* [BUG] Using another thread's JNIEnv */
    /* In real JNI: wrong_env->FindClass(...) is undefined */
    printf("JNI-BUG-07: using wrong thread env = %p\n", wrong_env);
}

/* ================================================================
 * Entry point
 * ================================================================ */
int main(void) {
    jni_bug_01_local_ref_after_pop();
    jni_bug_02_global_ref_leak();
    jni_bug_03_string_not_released();
    jni_bug_04_array_not_released();
    jni_bug_05_stale_ref_after_exception();
    jni_bug_06_critical_jni_violation();
    jni_bug_07_wrong_thread_env();
    return 0;
}
