/**
 * JNI Boundary Bug Test Cases (Self-contained)
 *
 * Tests for Java Native Interface (JNI) FFI boundary issues.
 * This file does NOT depend on <jni.h> — it simulates JNI patterns
 * using pure C function pointers, so it can be compiled to LLVM IR
 * without a JDK installation.
 *
 * Bug patterns:
 * - NULL check missing after FindClass/GetMethodID
 * - Exception check missing after JNI calls
 * - Global reference leak (NewGlobalRef without DeleteGlobalRef)
 * - Use after DeleteGlobalRef (UAF)
 * - AttachCurrentThread without DetachCurrentThread
 * - GetByteArrayElements without Release
 * - NewLocalRef not deleted in loop
 * - RegisterNatives signature mismatch
 */

#include <stdlib.h>
#include <string.h>

// Simulated JNI types (mirrors jni.h structure)
typedef signed char jbyte;
typedef int jint;
typedef void* jobject;
typedef void* jclass;
typedef void* jmethodID;
typedef void* jstring;
typedef void* jbyteArray;
typedef void* jobjectArray;
typedef int jsize;
typedef void* JNIEnv;
typedef void* JavaVM;

// Simulated JNI function table
struct JNINativeInterface {
    jclass (*FindClass)(JNIEnv*, const char*);
    jmethodID (*GetMethodID)(JNIEnv*, jclass, const char*, const char*);
    void (*CallVoidMethod)(JNIEnv*, jobject, jmethodID);
    const char* (*GetStringUTFChars)(JNIEnv*, jstring, void*);
    void (*ReleaseStringUTFChars)(JNIEnv*, jstring, const char*);
    jobject (*NewGlobalRef)(JNIEnv*, jobject);
    void (*DeleteGlobalRef)(JNIEnv*, jobject);
    int (*AttachCurrentThread)(JavaVM*, void**, void*);
    int (*DetachCurrentThread)(JavaVM*);
    jbyte* (*GetByteArrayElements)(JNIEnv*, jbyteArray, void*);
    void (*ReleaseByteArrayElements)(JNIEnv*, jbyteArray, jbyte*, jint);
    jobject (*GetObjectArrayElement)(JNIEnv*, jobjectArray, jsize);
    void (*DeleteLocalRef)(JNIEnv*, jobject);
    int (*ExceptionCheck)(JNIEnv*);
    void (*ExceptionDescribe)(JNIEnv*);
    void (*ExceptionClear)(JNIEnv*);
    jsize (*GetArrayLength)(JNIEnv*, jbyteArray);
};

// JNI_OnLoad entry point — detected by OmniScope as FFI boundary
__attribute__((visibility("default")))
jint JNI_OnLoad(JavaVM* vm, void* reserved) {
    return 1;
}

/* JNI-01: FindClass returns NULL without check */
void JNI_01_FindClass_Null_Check(JNIEnv* env) {
    struct JNINativeInterface* env_funcs = *(struct JNINativeInterface**)env;
    jclass clazz = env_funcs->FindClass(env, "com/example/MyClass");
    // BUG: No NULL check on clazz — FindClass may fail
    jmethodID method = env_funcs->GetMethodID(env, clazz, "process", "()V");
    env_funcs->CallVoidMethod(env, NULL, method);
}

/* JNI-02: GetMethodID returns NULL without check */
void JNI_02_GetMethodID_Null_Check(JNIEnv* env, jobject obj) {
    struct JNINativeInterface* env_funcs = *(struct JNINativeInterface**)env;
    jclass clazz = env_funcs->FindClass(env, "com/example/MyClass");
    if (clazz == NULL) return;
    jmethodID method = env_funcs->GetMethodID(env, clazz, "process", "()V");
    // BUG: No NULL check on method — GetMethodID may fail
    env_funcs->CallVoidMethod(env, obj, method);
}

/* JNI-03: ExceptionCheck missing after JNI call */
void JNI_03_ExceptionCheck_Missing(JNIEnv* env, jstring jstr) {
    struct JNINativeInterface* env_funcs = *(struct JNINativeInterface**)env;
    const char* str = env_funcs->GetStringUTFChars(env, jstr, NULL);
    // BUG: No ExceptionCheck after GetStringUTFChars
    // If exception occurred, str is NULL and accessing it crashes
    size_t len = strlen(str);
    (void)len;
    env_funcs->ReleaseStringUTFChars(env, jstr, str);
}

/* JNI-04: Global ref leak */
jobject JNI_04_NewGlobalRef_Leak(JNIEnv* env, jobject local_ref) {
    struct JNINativeInterface* env_funcs = *(struct JNINativeInterface**)env;
    jobject global_ref = env_funcs->NewGlobalRef(env, local_ref);
    // BUG: Global ref never deleted — memory leak
    return global_ref;
}

/* JNI-05: Use after DeleteGlobalRef (UAF) */
jobject global_cache = NULL;
void JNI_05_DeleteGlobalRef_Use_After(JNIEnv* env, jobject obj) {
    struct JNINativeInterface* env_funcs = *(struct JNINativeInterface**)env;
    if (global_cache != NULL) {
        env_funcs->DeleteGlobalRef(env, global_cache);
    }
    global_cache = env_funcs->NewGlobalRef(env, obj);
    // BUG: After DeleteGlobalRef, using global_cache is UAF
    // on second call with different obj
}

/* JNI-06: AttachCurrentThread without Detach */
JavaVM* cached_jvm = NULL;
void JNI_06_Attach_Without_Detach(JNIEnv* env) {
    JNIEnv* thread_env = NULL;
    // BUG: Thread exiting without DetachCurrentThread
    // cached_jvm->AttachCurrentThread is called but DetachCurrentThread is never called
    (void)thread_env;
    (void)env;
}

/* JNI-07: GetByteArrayElements without Release */
void JNI_07_GetByteArray_Not_Released(JNIEnv* env, jbyteArray arr) {
    struct JNINativeInterface* env_funcs = *(struct JNINativeInterface**)env;
    jbyte* elements = env_funcs->GetByteArrayElements(env, arr, NULL);
    // BUG: No ReleaseByteArrayElements call — JNI leak
    (void)elements;
}

/* JNI-08: NewLocalRef not deleted in loop */
void JNI_08_NewLocalRef_Loop_Leak(JNIEnv* env, jobjectArray arr) {
    struct JNINativeInterface* env_funcs = *(struct JNINativeInterface**)env;
    for (int i = 0; i < 10; i++) {
        jobject elem = env_funcs->GetObjectArrayElement(env, arr, i);
        // BUG: elem is new local ref, should delete after use
        // Missing: env_funcs->DeleteLocalRef(env, elem);
        (void)elem;
    }
}

/* JNI-09: ExceptionDescribe not called before ExceptionClear */
void JNI_09_ExceptionDescribe_Missing(JNIEnv* env) {
    struct JNINativeInterface* env_funcs = *(struct JNINativeInterface**)env;
    jclass clazz = env_funcs->FindClass(env, "NonExistent");
    if (env_funcs->ExceptionCheck(env)) {
        // BUG: Should call ExceptionDescribe() for logging
        // then ExceptionClear() to continue JNI calls
        env_funcs->ExceptionClear(env);
    }
    (void)clazz;
}

/* JNI-10: RegisterNatives with NULL function pointer */
typedef struct {
    const char* name;
    const char* signature;
    void* fnPtr;
} JNINativeMethod;

void JNI_10_RegisterNatives_Null_FnPtr(JNIEnv* env) {
    struct JNINativeInterface* env_funcs = *(struct JNINativeInterface**)env;
    jclass clazz = env_funcs->FindClass(env, "com/example/MyClass");
    if (clazz == NULL) return;
    JNINativeMethod methods[] = {
        { "nativeMethod", "()V", NULL }
    };
    // BUG: fnPtr is NULL — runtime crash when method is invoked
    // RegisterNatives itself doesn't validate fnPtr
    (void)methods;
}
