/**
 * JNI Boundary Bug Test Cases
 *
 * Tests for Java Native Interface (JNI) FFI boundary issues:
 * - NULL check missing after FindClass/GetMethodID
 * - Exception check missing after JNI calls
 * - Global reference leak (NewGlobalRef without DeleteGlobalRef)
 * - Use after DeleteGlobalRef (UAF)
 * - AttachCurrentThread without DetachCurrentThread
 */

#include <jni.h>
#include <stdlib.h>
#include <string.h>

JavaVM* cached_jvm = NULL;

/* JNI-01: FindClass returns NULL without check */
void JNI_01_FindClass_Null_Check(JNIEnv* env) {
    jclass clazz = (*env)->FindClass(env, "com/example/MyClass");
    // BUG: No NULL check on clazz
    jmethodID method = (*env)->GetMethodID(env, clazz, "process", "()V");
    // Crash if clazz is NULL - FindClass failed and didn't exception check
    (*env)->CallVoidMethod(env, NULL, method);
}

/* JNI-02: GetMethodID returns NULL without check */
void JNI_02_GetMethodID_Null_Check(JNIEnv* env, jobject obj) {
    jclass clazz = (*env)->FindClass(env, "com/example/MyClass");
    if (clazz == NULL) return;
    jmethodID method = (*env)->GetMethodID(env, clazz, "process", "()V");
    // BUG: No NULL check on method
    (*env)->CallVoidMethod(env, obj, method);
}

/* JNI-03: ExceptionCheck missing after JNI call */
void JNI_03_ExceptionCheck_Missing(JNIEnv* env, jstring jstr) {
    const char* str = (*env)->GetStringUTFChars(env, jstr, NULL);
    // BUG: No ExceptionCheck after GetStringUTFChars
    // If exception occurred, str is NULL and accessing it crashes
    printf("String length: %zu\n", strlen(str));
    (*env)->ReleaseStringUTFChars(env, jstr, str);
}

/* JNI-04: Global ref leak */
jobject JNI_04_NewGlobalRef_Leak(JNIEnv* env, jobject local_ref) {
    jobject global_ref = (*env)->NewGlobalRef(env, local_ref);
    // BUG: Global ref never deleted - memory leak
    return global_ref;
}

/* JNI-05: Use after DeleteGlobalRef (UAF) */
jobject global_cache = NULL;
void JNI_05_DeleteGlobalRef_Use_After(JNIEnv* env, jobject obj) {
    if (global_cache != NULL) {
        (*env)->DeleteGlobalRef(env, global_cache);
    }
    global_cache = (*env)->NewGlobalRef(env, obj);
    // BUG: After DeleteGlobalRef, using global_cache is UAF
    // This happens on second call with different obj
}

/* JNI-06: AttachCurrentThread without Detach */
void JNI_06_Attach_Without_Detach(JNIEnv* env) {
    JNIEnv* thread_env = NULL;
    JavaVMAttachArgs args = { JNI_VERSION_1_6, "WorkerThread", NULL };
    (*cached_jvm)->AttachCurrentThread(cached_jvm, (void**)&thread_env, &args);
    // BUG: Thread exiting without DetachCurrentThread - JNI reference leak
    // Should call DetachCurrentThread before thread exits
}

/* JNI-07: GetByteArrayElements without Release */
void JNI_07_GetByteArray_Not_Released(JNIEnv* env, jbyteArray arr) {
    jbyte* elements = (*env)->GetByteArrayElements(env, arr, NULL);
    size_t len = (*env)->GetArrayLength(env, arr);
    // BUG: No ReleaseByteArrayElements call - JNI leak
    // Should call ReleaseByteArrayElements when done
}

/* JNI-08: NewLocalRef not deleted in loop */
void JNI_08_NewLocalRef_Loop_Leak(JNIEnv* env, jobjectArray arr) {
    jsize len = (*env)->GetArrayLength(env, arr);
    for (jsize i = 0; i < len; i++) {
        jobject elem = (*env)->GetObjectArrayElement(env, arr, i);
        // BUG: elem is new local ref, should delete
        process_element(elem);
        // Missing: (*env)->DeleteLocalRef(env, elem);
    }
}

/* JNI-09: ExceptionDescribe not called */
void JNI_09_ExceptionDescribe_Missing(JNIEnv* env) {
    jclass clazz = (*env)->FindClass(env, "NonExistent");
    if ((*env)->ExceptionOccurred(env)) {
        // BUG: Should call ExceptionDescribe() for logging
        // then ExceptionClear() to continue JNI calls
        (*env)->ExceptionClear(env);
    }
}

/* JNI-10: RegisterNatives signature mismatch */
typedef void (*native_fn)(JNIEnv*, jobject);
void JNI_10_RegisterNatives_Signature_Mismatch(JNIEnv* env) {
    JNINativeMethod methods[] = {
        { "nativeMethod", "()V", NULL }
    };
    jclass clazz = (*env)->FindClass(env, "com/example/MyClass");
    if (clazz == NULL) return;
    // BUG: If nativeFn is NULL or wrong signature, runtime crash
    (*env)->RegisterNatives(env, clazz, methods, 1);
}
