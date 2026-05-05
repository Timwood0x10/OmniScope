// OmniScope v0.1.7 — Minimal jni.h Stub for Corpus Compilation
//
// Provides just enough type/macro definitions to compile v017_jni_boundary.c.
// NOT a real JNI implementation.
//
// Real JNI convention:
//   JNIEnv = const struct JNINativeInterface*  (pointer to func table)
//   Functions receive: JNIEnv* env  →  (*env) = func table  →  (*env)->Func(...)

#ifndef JNI_H_STUB
#define JNI_H_STUB

#include <stdint.h>
#include <stddef.h>
#include <stdio.h>
#include <stdarg.h>
#include <pthread.h>

#define JNIEXPORT  __attribute__((visibility("default")))
#define JNICALL
#define JNI_VERSION_1_8  0x00010008

typedef int8_t   jbyte;
typedef int16_t  jshort;
typedef int32_t  jint;
typedef int32_t  jsize;
typedef int64_t  jlong;
typedef float    jfloat;
typedef double   jdouble;
typedef uint16_t jchar;
typedef uint8_t  jboolean;

typedef void* jobject;
typedef void* jclass;
typedef void* jstring;
typedef void* jthrowable;
typedef void* jvalue;
typedef void* jweak;
typedef void* jarray;
typedef jarray  jintArray;
typedef void*   jmethodID;
typedef void*   jfieldID;

// JNI function table — (*env) points here
struct JNINativeInterface_ {
    void*       reserved0;
    void*       reserved1;
    void*       reserved2;
    void*       reserved3;
    jclass      (*FindClass)(void*, const char*);
    jmethodID   (*GetMethodID)(void*, jclass, const char*, const char*);
    jfieldID    (*GetFieldID)(void*, jclass, const char*, const char*);
    jobject     (*NewObject)(void*, jclass, jmethodID, ...);
    void        (*CallVoidMethod)(void*, jobject, jmethodID, ...);
    jlong       (*GetLongField)(void*, jobject, jfieldID);
    void        (*SetLongField)(void*, jobject, jfieldID, jlong);
    jclass      (*GetObjectClass)(void*, jobject);
    jstring     (*NewStringUTF)(void*, const char*);
    const char* (*GetStringUTFChars)(void*, jstring, jboolean*);
    void        (*ReleaseStringUTFChars)(void*, jstring, const char*);
    jsize       (*GetArrayLength)(void*, jarray);
    jint*       (*GetIntArrayElements)(void*, jintArray, jboolean*);
    void        (*ReleaseIntArrayElements)(void*, jintArray, jint*, jint);
    void        (*DeleteLocalRef)(void*, jobject);
    jint        (*GetJavaVM)(void*, void**);
};

// JNIEnv = pointer to function table (real JNI convention)
typedef const struct JNINativeInterface_* JNIEnv;

struct InvokeInterface_ {
    void* reserved0;
    void* reserved1;
    void* reserved2;
    jint  (*GetEnv)(const void*, void**, jint);
    jint  (*AttachCurrentThread)(const void*, void**, void*);
};
typedef const struct InvokeInterface_* JavaVM;

#endif // JNI_H_STUB
