; ModuleID = '/Users/scc/code/zigcode/OmniScope/corpus/red_team_test/red_team_swift_ffi.ll'
source_filename = "/Users/scc/code/zigcode/OmniScope/corpus/red_team_test/red_team_swift_ffi.ll"
target datalayout = "e-m:o-i64:64-i128:128-n32:64-S128-Fn32"
target triple = "arm64-apple-macosx15.0.0"

%TSPys5UInt8VGSg = type <{ [8 x i8] }>
%TSRys5UInt8VGSg = type <{ [16 x i8], [1 x i8] }>
%struct._SwiftEmptyArrayStorage = type { %struct.HeapObject, %struct._SwiftArrayBodyStorage }
%struct.HeapObject = type { ptr, %struct.InlineRefCountsPlaceholder }
%struct.InlineRefCountsPlaceholder = type { i64 }
%struct._SwiftArrayBodyStorage = type { i64, i64 }
%swift.full_existential_type = type { ptr, %swift.type }
%swift.type = type { i64 }
%objc_class = type { ptr, ptr, ptr, ptr, ptr }
%swift.type_descriptor = type opaque
%swift.opaque = type opaque
%swift.method_descriptor = type { i32, i32 }
%swift.protocol_conformance_descriptor = type { i32, i32, i32, i32 }
%swift.type_metadata_record = type { i32 }
%T18red_team_swift_ffi11SwiftObjectC = type <{ %swift.refcounted, %TSi }>
%swift.refcounted = type { ptr, i64 }
%TSi = type <{ i64 }>
%"$s18red_team_swift_ffi11SwiftObjectC5valueSivM.Frame" = type { [24 x i8] }
%Any = type { [24 x i8], ptr }
%TSS = type <{ %Ts11_StringGutsV }>
%Ts11_StringGutsV = type <{ %Ts13_StringObjectV }>
%Ts13_StringObjectV = type <{ %Ts6UInt64V, ptr }>
%Ts6UInt64V = type <{ i64 }>
%TSa = type <{ %Ts12_ArrayBufferV }>
%Ts12_ArrayBufferV = type <{ %Ts14_BridgeStorageV }>
%Ts14_BridgeStorageV = type <{ ptr }>
%swift.metadata_response = type { ptr, i64 }
%T18red_team_swift_ffi11SwiftObjectCSg = type <{ [8 x i8] }>
%swift.unowned = type { ptr }
%Ts26DefaultStringInterpolationV = type <{ %TSS }>
%swift.weak = type { ptr }
%Ts5UInt8V = type <{ i8 }>
%swift.vwtable = type { ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, i64, i64, i32, i32 }
%TSRys5UInt8VG = type <{ %TSPys5UInt8VGSg, %TSi }>
%TSv = type <{ ptr }>

@"$s18red_team_swift_ffi13g_escaped_ptrSPys5UInt8VGSgvp" = hidden global %TSPys5UInt8VGSg zeroinitializer, align 8
@"$s18red_team_swift_ffi14g_array_bufferSRys5UInt8VGSgvp" = hidden global %TSRys5UInt8VGSg zeroinitializer, align 8
@_swiftEmptyArrayStorage = external global %struct._SwiftEmptyArrayStorage, align 8
@"$sypN" = external global %swift.full_existential_type
@".str.23.SwiftObject deallocated" = private unnamed_addr constant [24 x i8] c"SwiftObject deallocated\00"
@"$sSSN" = external global %swift.type, align 8
@".str.14.SWIFT-BUG-01: " = private unnamed_addr constant [15 x i8] c"SWIFT-BUG-01: \00"
@"$sSiN" = external global %swift.type, align 8
@"$sSis23CustomStringConvertiblesWP" = external global ptr, align 8
@.str.0. = private unnamed_addr constant [1 x i8] zeroinitializer
@".str.14.SWIFT-BUG-02: " = private unnamed_addr constant [15 x i8] c"SWIFT-BUG-02: \00"
@".str.43.red_team_swift_ffi/red_team_swift_ffi.swift" = private unnamed_addr constant [44 x i8] c"red_team_swift_ffi/red_team_swift_ffi.swift\00"
@".str.57.Unexpectedly found nil while unwrapping an Optional value" = private unnamed_addr constant [58 x i8] c"Unexpectedly found nil while unwrapping an Optional value\00"
@".str.11.Fatal error" = private unnamed_addr constant [12 x i8] c"Fatal error\00"
@"$ss5UInt8VN" = external global %swift.type, align 8
@".str.14.SWIFT-BUG-03: " = private unnamed_addr constant [15 x i8] c"SWIFT-BUG-03: \00"
@"$ss5UInt8Vs23CustomStringConvertiblesWP" = external global ptr, align 8
@".str.14.bridged string" = private unnamed_addr constant [15 x i8] c"bridged string\00"
@"$sSo8NSStringCML" = linkonce_odr hidden global ptr null, align 8
@"OBJC_CLASS_REF_$_NSString" = private externally_initialized global ptr @"OBJC_CLASS_$_NSString", section "__DATA,__objc_classrefs,regular,no_dead_strip", align 8
@"OBJC_CLASS_$_NSString" = external global %objc_class, align 8
@".str.14.SWIFT-BUG-04: " = private unnamed_addr constant [15 x i8] c"SWIFT-BUG-04: \00"
@"$sSSs23CustomStringConvertiblesWP" = external global ptr, align 8
@"$sSSs20TextOutputStreamablesWP" = external global ptr, align 8
@"$ss5UInt8VMn" = external global %swift.type_descriptor, align 4
@"got.$ss5UInt8VMn" = private unnamed_addr constant ptr @"$ss5UInt8VMn"
@"symbolic Say_____G s5UInt8V" = linkonce_odr hidden constant <{ [3 x i8], i8, i32, [1 x i8], i8 }> <{ [3 x i8] c"Say", i8 2, i32 trunc (i64 sub (i64 ptrtoint (ptr @"got.$ss5UInt8VMn" to i64), i64 ptrtoint (ptr getelementptr inbounds (<{ [3 x i8], i8, i32, [1 x i8], i8 }>, ptr @"symbolic Say_____G s5UInt8V", i32 0, i32 2) to i64)) to i32), [1 x i8] c"G", i8 0 }>, section "__TEXT,__swift5_typeref, regular", no_sanitize_address, align 2
@"$sSays5UInt8VGMd" = linkonce_odr hidden global { ptr } zeroinitializer, align 8
@"$sSays5UInt8VGMR" = linkonce_odr hidden constant { i32, i32 } { i32 trunc (i64 sub (i64 ptrtoint (ptr @"symbolic Say_____G s5UInt8V" to i64), i64 ptrtoint (ptr @"$sSays5UInt8VGMR" to i64)) to i32), i32 9 }, align 8
@"$ss5NeverON" = external global %swift.type, align 8
@"$sytN" = external global %swift.full_existential_type
@"$ss5NeverOs5ErrorsWP" = external global ptr, align 8
@".str.14.SWIFT-BUG-05: " = private unnamed_addr constant [15 x i8] c"SWIFT-BUG-05: \00"
@".str.14.SWIFT-BUG-07: " = private unnamed_addr constant [15 x i8] c"SWIFT-BUG-07: \00"
@".str.39.Swift/arm64e-apple-macos.swiftinterface" = private unnamed_addr constant [40 x i8] c"Swift/arm64e-apple-macos.swiftinterface\00"
@"\01l_entry_point" = private constant { i32, i32 } { i32 trunc (i64 sub (i64 ptrtoint (ptr @main to i64), i64 ptrtoint (ptr @"\01l_entry_point" to i64)) to i32), i32 0 }, section "__TEXT, __swift5_entry, regular, no_dead_strip", align 4
@"$s18red_team_swift_ffi11SwiftObjectC5valueSivpWvd" = hidden constant i64 16, align 8
@"$sBoWV" = external global ptr, align 8
@"$s18red_team_swift_ffi11SwiftObjectCMm" = hidden global %objc_class { ptr @"OBJC_METACLASS_$__TtCs12_SwiftObject", ptr @"OBJC_METACLASS_$__TtCs12_SwiftObject", ptr @_objc_empty_cache, ptr null, ptr @_METACLASS_DATA__TtC18red_team_swift_ffi11SwiftObject }, align 8
@"OBJC_CLASS_$__TtCs12_SwiftObject" = external global %objc_class, align 8
@_objc_empty_cache = external global %swift.opaque
@"OBJC_METACLASS_$__TtCs12_SwiftObject" = external global %objc_class, align 8
@.str.37._TtC18red_team_swift_ffi11SwiftObject = private unnamed_addr constant [38 x i8] c"_TtC18red_team_swift_ffi11SwiftObject\00"
@_METACLASS_DATA__TtC18red_team_swift_ffi11SwiftObject = internal constant { i32, i32, i32, i32, ptr, ptr, ptr, ptr, ptr, ptr, ptr } { i32 129, i32 40, i32 40, i32 0, ptr null, ptr @.str.37._TtC18red_team_swift_ffi11SwiftObject, ptr null, ptr null, ptr null, ptr null, ptr null }, section "__DATA, __objc_const", align 8
@.str.5.value = private unnamed_addr constant [6 x i8] c"value\00"
@_IVARS__TtC18red_team_swift_ffi11SwiftObject = internal constant { i32, i32, [1 x { ptr, ptr, ptr, i32, i32 }] } { i32 32, i32 1, [1 x { ptr, ptr, ptr, i32, i32 }] [{ ptr, ptr, ptr, i32, i32 } { ptr @"$s18red_team_swift_ffi11SwiftObjectC5valueSivpWvd", ptr @.str.5.value, ptr @.str.0., i32 3, i32 8 }] }, section "__DATA, __objc_const", align 8
@_DATA__TtC18red_team_swift_ffi11SwiftObject = internal constant { i32, i32, i32, i32, ptr, ptr, ptr, ptr, ptr, ptr, ptr } { i32 128, i32 16, i32 24, i32 0, ptr null, ptr @.str.37._TtC18red_team_swift_ffi11SwiftObject, ptr null, ptr null, ptr @_IVARS__TtC18red_team_swift_ffi11SwiftObject, ptr null, ptr null }, section "__DATA, __objc_const", align 8
@.str.18.red_team_swift_ffi = private constant [19 x i8] c"red_team_swift_ffi\00"
@"$s18red_team_swift_ffiMXM" = linkonce_odr hidden constant <{ i32, i32, i32 }> <{ i32 0, i32 0, i32 trunc (i64 sub (i64 ptrtoint (ptr @.str.18.red_team_swift_ffi to i64), i64 ptrtoint (ptr getelementptr inbounds (<{ i32, i32, i32 }>, ptr @"$s18red_team_swift_ffiMXM", i32 0, i32 2) to i64)) to i32) }>, section "__TEXT,__constg_swiftt", align 4
@.str.11.SwiftObject = private constant [12 x i8] c"SwiftObject\00"
@"$s18red_team_swift_ffi11SwiftObjectCMn" = hidden constant <{ i32, i32, i32, i32, i32, i32, i32, i32, i32, i32, i32, i32, i32, %swift.method_descriptor, %swift.method_descriptor, %swift.method_descriptor, %swift.method_descriptor }> <{ i32 -2147483568, i32 trunc (i64 sub (i64 ptrtoint (ptr @"$s18red_team_swift_ffiMXM" to i64), i64 ptrtoint (ptr getelementptr inbounds (<{ i32, i32, i32, i32, i32, i32, i32, i32, i32, i32, i32, i32, i32, %swift.method_descriptor, %swift.method_descriptor, %swift.method_descriptor, %swift.method_descriptor }>, ptr @"$s18red_team_swift_ffi11SwiftObjectCMn", i32 0, i32 1) to i64)) to i32), i32 trunc (i64 sub (i64 ptrtoint (ptr @.str.11.SwiftObject to i64), i64 ptrtoint (ptr getelementptr inbounds (<{ i32, i32, i32, i32, i32, i32, i32, i32, i32, i32, i32, i32, i32, %swift.method_descriptor, %swift.method_descriptor, %swift.method_descriptor, %swift.method_descriptor }>, ptr @"$s18red_team_swift_ffi11SwiftObjectCMn", i32 0, i32 2) to i64)) to i32), i32 trunc (i64 sub (i64 ptrtoint (ptr @"$s18red_team_swift_ffi11SwiftObjectCMa" to i64), i64 ptrtoint (ptr getelementptr inbounds (<{ i32, i32, i32, i32, i32, i32, i32, i32, i32, i32, i32, i32, i32, %swift.method_descriptor, %swift.method_descriptor, %swift.method_descriptor, %swift.method_descriptor }>, ptr @"$s18red_team_swift_ffi11SwiftObjectCMn", i32 0, i32 3) to i64)) to i32), i32 trunc (i64 sub (i64 ptrtoint (ptr @"$s18red_team_swift_ffi11SwiftObjectCMF" to i64), i64 ptrtoint (ptr getelementptr inbounds (<{ i32, i32, i32, i32, i32, i32, i32, i32, i32, i32, i32, i32, i32, %swift.method_descriptor, %swift.method_descriptor, %swift.method_descriptor, %swift.method_descriptor }>, ptr @"$s18red_team_swift_ffi11SwiftObjectCMn", i32 0, i32 4) to i64)) to i32), i32 0, i32 3, i32 15, i32 5, i32 1, i32 10, i32 11, i32 4, %swift.method_descriptor { i32 18, i32 trunc (i64 sub (i64 ptrtoint (ptr @"$s18red_team_swift_ffi11SwiftObjectC5valueSivg" to i64), i64 ptrtoint (ptr getelementptr inbounds (<{ i32, i32, i32, i32, i32, i32, i32, i32, i32, i32, i32, i32, i32, %swift.method_descriptor, %swift.method_descriptor, %swift.method_descriptor, %swift.method_descriptor }>, ptr @"$s18red_team_swift_ffi11SwiftObjectCMn", i32 0, i32 13, i32 1) to i64)) to i32) }, %swift.method_descriptor { i32 19, i32 trunc (i64 sub (i64 ptrtoint (ptr @"$s18red_team_swift_ffi11SwiftObjectC5valueSivs" to i64), i64 ptrtoint (ptr getelementptr inbounds (<{ i32, i32, i32, i32, i32, i32, i32, i32, i32, i32, i32, i32, i32, %swift.method_descriptor, %swift.method_descriptor, %swift.method_descriptor, %swift.method_descriptor }>, ptr @"$s18red_team_swift_ffi11SwiftObjectCMn", i32 0, i32 14, i32 1) to i64)) to i32) }, %swift.method_descriptor { i32 20, i32 trunc (i64 sub (i64 ptrtoint (ptr @"$s18red_team_swift_ffi11SwiftObjectC5valueSivM" to i64), i64 ptrtoint (ptr getelementptr inbounds (<{ i32, i32, i32, i32, i32, i32, i32, i32, i32, i32, i32, i32, i32, %swift.method_descriptor, %swift.method_descriptor, %swift.method_descriptor, %swift.method_descriptor }>, ptr @"$s18red_team_swift_ffi11SwiftObjectCMn", i32 0, i32 15, i32 1) to i64)) to i32) }, %swift.method_descriptor { i32 1, i32 trunc (i64 sub (i64 ptrtoint (ptr @"$s18red_team_swift_ffi11SwiftObjectCACycfC" to i64), i64 ptrtoint (ptr getelementptr inbounds (<{ i32, i32, i32, i32, i32, i32, i32, i32, i32, i32, i32, i32, i32, %swift.method_descriptor, %swift.method_descriptor, %swift.method_descriptor, %swift.method_descriptor }>, ptr @"$s18red_team_swift_ffi11SwiftObjectCMn", i32 0, i32 16, i32 1) to i64)) to i32) } }>, section "__TEXT,__constg_swiftt", align 4
@"$s18red_team_swift_ffi11SwiftObjectCMf" = internal global <{ ptr, ptr, ptr, i64, ptr, ptr, ptr, ptr, i32, i32, i32, i16, i16, i32, i32, ptr, ptr, i64, ptr, ptr, ptr, ptr }> <{ ptr null, ptr @"$s18red_team_swift_ffi11SwiftObjectCfD", ptr @"$sBoWV", i64 ptrtoint (ptr @"$s18red_team_swift_ffi11SwiftObjectCMm" to i64), ptr @"OBJC_CLASS_$__TtCs12_SwiftObject", ptr @_objc_empty_cache, ptr null, ptr getelementptr (i8, ptr @_DATA__TtC18red_team_swift_ffi11SwiftObject, i64 2), i32 2, i32 0, i32 24, i16 7, i16 0, i32 144, i32 24, ptr @"$s18red_team_swift_ffi11SwiftObjectCMn", ptr null, i64 16, ptr @"$s18red_team_swift_ffi11SwiftObjectC5valueSivg", ptr @"$s18red_team_swift_ffi11SwiftObjectC5valueSivs", ptr @"$s18red_team_swift_ffi11SwiftObjectC5valueSivM", ptr @"$s18red_team_swift_ffi11SwiftObjectCACycfC" }>, align 8
@"symbolic _____ 18red_team_swift_ffi11SwiftObjectC" = linkonce_odr hidden constant <{ i8, i32, i8 }> <{ i8 1, i32 trunc (i64 sub (i64 ptrtoint (ptr @"$s18red_team_swift_ffi11SwiftObjectCMn" to i64), i64 ptrtoint (ptr getelementptr inbounds (<{ i8, i32, i8 }>, ptr @"symbolic _____ 18red_team_swift_ffi11SwiftObjectC", i32 0, i32 1) to i64)) to i32), i8 0 }>, section "__TEXT,__swift5_typeref, regular", no_sanitize_address, align 2
@"symbolic Si" = linkonce_odr hidden constant <{ [2 x i8], i8 }> <{ [2 x i8] c"Si", i8 0 }>, section "__TEXT,__swift5_typeref, regular", no_sanitize_address, align 2
@0 = private constant [6 x i8] c"value\00", section "__TEXT,__swift5_reflstr, regular", no_sanitize_address
@"$s18red_team_swift_ffi11SwiftObjectCMF" = internal constant { i32, i32, i16, i16, i32, i32, i32, i32 } { i32 trunc (i64 sub (i64 ptrtoint (ptr @"symbolic _____ 18red_team_swift_ffi11SwiftObjectC" to i64), i64 ptrtoint (ptr @"$s18red_team_swift_ffi11SwiftObjectCMF" to i64)) to i32), i32 0, i16 1, i16 12, i32 1, i32 2, i32 trunc (i64 sub (i64 ptrtoint (ptr @"symbolic Si" to i64), i64 ptrtoint (ptr getelementptr inbounds ({ i32, i32, i16, i16, i32, i32, i32, i32 }, ptr @"$s18red_team_swift_ffi11SwiftObjectCMF", i32 0, i32 6) to i64)) to i32), i32 trunc (i64 sub (i64 ptrtoint (ptr @0 to i64), i64 ptrtoint (ptr getelementptr inbounds ({ i32, i32, i16, i16, i32, i32, i32, i32 }, ptr @"$s18red_team_swift_ffi11SwiftObjectCMF", i32 0, i32 7) to i64)) to i32) }, section "__TEXT,__swift5_fieldmd, regular", no_sanitize_address, align 4
@"_swift_FORCE_LOAD_$_swiftFoundation_$_red_team_swift_ffi" = weak_odr hidden constant ptr @"_swift_FORCE_LOAD_$_swiftFoundation"
@"_swift_FORCE_LOAD_$_swift_Builtin_float_$_red_team_swift_ffi" = weak_odr hidden constant ptr @"_swift_FORCE_LOAD_$_swift_Builtin_float"
@"_swift_FORCE_LOAD_$_swiftObjectiveC_$_red_team_swift_ffi" = weak_odr hidden constant ptr @"_swift_FORCE_LOAD_$_swiftObjectiveC"
@"_swift_FORCE_LOAD_$_swiftCoreFoundation_$_red_team_swift_ffi" = weak_odr hidden constant ptr @"_swift_FORCE_LOAD_$_swiftCoreFoundation"
@"_swift_FORCE_LOAD_$_swiftDispatch_$_red_team_swift_ffi" = weak_odr hidden constant ptr @"_swift_FORCE_LOAD_$_swiftDispatch"
@"_swift_FORCE_LOAD_$_swiftXPC_$_red_team_swift_ffi" = weak_odr hidden constant ptr @"_swift_FORCE_LOAD_$_swiftXPC"
@"_swift_FORCE_LOAD_$_swiftIOKit_$_red_team_swift_ffi" = weak_odr hidden constant ptr @"_swift_FORCE_LOAD_$_swiftIOKit"
@"$ss12_ArrayBufferVyxGSTsMc" = external global %swift.protocol_conformance_descriptor, align 4
@".str.10.callback: " = private unnamed_addr constant [11 x i8] c"callback: \00"
@".str.1.\0A" = private unnamed_addr constant [2 x i8] c"\0A\00"
@".str.1. " = private unnamed_addr constant [2 x i8] c" \00"
@"$s18red_team_swift_ffi11SwiftObjectCHn" = private constant %swift.type_metadata_record { i32 trunc (i64 sub (i64 ptrtoint (ptr @"$s18red_team_swift_ffi11SwiftObjectCMn" to i64), i64 ptrtoint (ptr @"$s18red_team_swift_ffi11SwiftObjectCHn" to i64)) to i32) }, section "__TEXT, __swift5_types, regular", no_sanitize_address, align 4
@__swift_reflection_version = linkonce_odr hidden constant i16 3
@"objc_classes_$s18red_team_swift_ffi11SwiftObjectCN" = internal global ptr @"$s18red_team_swift_ffi11SwiftObjectCN", section "__DATA,__objc_classlist,regular,no_dead_strip", no_sanitize_address, align 8
@llvm.used = appending global [19 x ptr] [ptr @"$s18red_team_swift_ffi13g_escaped_ptrSPys5UInt8VGSgvp", ptr @"$s18red_team_swift_ffi14g_array_bufferSRys5UInt8VGSgvp", ptr @main, ptr @"$s18red_team_swift_ffi11SwiftObjectC5valueSivg", ptr @"$s18red_team_swift_ffi11SwiftObjectC5valueSivs", ptr @"$s18red_team_swift_ffi11SwiftObjectCfd", ptr @"$s18red_team_swift_ffi11SwiftObjectCfD", ptr @"\01l_entry_point", ptr @"$s18red_team_swift_ffi11SwiftObjectCMF", ptr @"_swift_FORCE_LOAD_$_swiftFoundation_$_red_team_swift_ffi", ptr @"_swift_FORCE_LOAD_$_swift_Builtin_float_$_red_team_swift_ffi", ptr @"_swift_FORCE_LOAD_$_swiftObjectiveC_$_red_team_swift_ffi", ptr @"_swift_FORCE_LOAD_$_swiftCoreFoundation_$_red_team_swift_ffi", ptr @"_swift_FORCE_LOAD_$_swiftDispatch_$_red_team_swift_ffi", ptr @"_swift_FORCE_LOAD_$_swiftXPC_$_red_team_swift_ffi", ptr @"_swift_FORCE_LOAD_$_swiftIOKit_$_red_team_swift_ffi", ptr @"$s18red_team_swift_ffi11SwiftObjectCHn", ptr @__swift_reflection_version, ptr @"objc_classes_$s18red_team_swift_ffi11SwiftObjectCN"], section "llvm.metadata"
@llvm.compiler.used = appending global [7 x ptr] [ptr @"OBJC_CLASS_REF_$_NSString", ptr @"$s18red_team_swift_ffi11SwiftObjectC5valueSivgTq", ptr @"$s18red_team_swift_ffi11SwiftObjectC5valueSivsTq", ptr @"$s18red_team_swift_ffi11SwiftObjectC5valueSivMTq", ptr @"$s18red_team_swift_ffi11SwiftObjectCACycfCTq", ptr @"$s18red_team_swift_ffi11SwiftObjectCMf", ptr @"$s18red_team_swift_ffi11SwiftObjectCN"], section "llvm.metadata"

@"$s18red_team_swift_ffi11SwiftObjectC5valueSivgTq" = hidden alias %swift.method_descriptor, getelementptr inbounds (<{ i32, i32, i32, i32, i32, i32, i32, i32, i32, i32, i32, i32, i32, %swift.method_descriptor, %swift.method_descriptor, %swift.method_descriptor, %swift.method_descriptor }>, ptr @"$s18red_team_swift_ffi11SwiftObjectCMn", i32 0, i32 13)
@"$s18red_team_swift_ffi11SwiftObjectC5valueSivsTq" = hidden alias %swift.method_descriptor, getelementptr inbounds (<{ i32, i32, i32, i32, i32, i32, i32, i32, i32, i32, i32, i32, i32, %swift.method_descriptor, %swift.method_descriptor, %swift.method_descriptor, %swift.method_descriptor }>, ptr @"$s18red_team_swift_ffi11SwiftObjectCMn", i32 0, i32 14)
@"$s18red_team_swift_ffi11SwiftObjectC5valueSivMTq" = hidden alias %swift.method_descriptor, getelementptr inbounds (<{ i32, i32, i32, i32, i32, i32, i32, i32, i32, i32, i32, i32, i32, %swift.method_descriptor, %swift.method_descriptor, %swift.method_descriptor, %swift.method_descriptor }>, ptr @"$s18red_team_swift_ffi11SwiftObjectCMn", i32 0, i32 15)
@"$s18red_team_swift_ffi11SwiftObjectCACycfCTq" = hidden alias %swift.method_descriptor, getelementptr inbounds (<{ i32, i32, i32, i32, i32, i32, i32, i32, i32, i32, i32, i32, i32, %swift.method_descriptor, %swift.method_descriptor, %swift.method_descriptor, %swift.method_descriptor }>, ptr @"$s18red_team_swift_ffi11SwiftObjectCMn", i32 0, i32 16)
@"$s18red_team_swift_ffi11SwiftObjectCN" = hidden alias %swift.type, getelementptr inbounds (<{ ptr, ptr, ptr, i64, ptr, ptr, ptr, ptr, i32, i32, i32, i16, i16, i32, i32, ptr, ptr, i64, ptr, ptr, ptr, ptr }>, ptr @"$s18red_team_swift_ffi11SwiftObjectCMf", i32 0, i32 3)

define i32 @main(i32 %0, ptr %1) #0 {
entry:
  store i64 0, ptr @"$s18red_team_swift_ffi13g_escaped_ptrSPys5UInt8VGSgvp", align 8
  store i64 0, ptr @"$s18red_team_swift_ffi14g_array_bufferSRys5UInt8VGSgvp", align 8
  store i64 0, ptr getelementptr inbounds ({ i64, i64 }, ptr @"$s18red_team_swift_ffi14g_array_bufferSRys5UInt8VGSgvp", i32 0, i32 1), align 8
  store i1 true, ptr getelementptr inbounds (%TSRys5UInt8VGSg, ptr @"$s18red_team_swift_ffi14g_array_bufferSRys5UInt8VGSgvp", i32 0, i32 1), align 8
  call swiftcc void @"$s18red_team_swift_ffi4mainyyF"()
  ret i32 0
}

define hidden swiftcc void @"$s18red_team_swift_ffi4mainyyF"() #0 {
entry:
  call swiftcc void @"$s18red_team_swift_ffi0C19_bug_01_unowned_uafyyF"()
  call swiftcc void @"$s18red_team_swift_ffi0C17_bug_02_weak_raceyyF"()
  call swiftcc void @"$s18red_team_swift_ffi0C19_bug_03_raw_ptr_uafyyF"()
  call swiftcc void @"$s18red_team_swift_ffi0C27_bug_04_bridge_over_releaseyyF"()
  call swiftcc void @"$s18red_team_swift_ffi0C22_bug_05_pointer_escapeyyF"()
  call swiftcc void @"$s18red_team_swift_ffi0C21_bug_06_objc_callbackyyF"()
  call swiftcc void @"$s18red_team_swift_ffi0C20_bug_07_array_escapeyyF"()
  ret void
}

define hidden swiftcc i64 @"$s18red_team_swift_ffi11SwiftObjectC5valueSivpfi"() #0 {
entry:
  ret i64 42
}

define hidden swiftcc i64 @"$s18red_team_swift_ffi11SwiftObjectC5valueSivg"(ptr swiftself %0) #0 {
entry:
  %access-scratch = alloca [24 x i8], align 8
  %1 = getelementptr inbounds %T18red_team_swift_ffi11SwiftObjectC, ptr %0, i32 0, i32 1
  call void @llvm.lifetime.start.p0(i64 -1, ptr %access-scratch)
  call void @swift_beginAccess(ptr %1, ptr %access-scratch, i64 32, ptr null) #3
  %._value = getelementptr inbounds %TSi, ptr %1, i32 0, i32 0
  %2 = load i64, ptr %._value, align 8
  call void @swift_endAccess(ptr %access-scratch) #3
  call void @llvm.lifetime.end.p0(i64 -1, ptr %access-scratch)
  ret i64 %2
}

define hidden swiftcc void @"$s18red_team_swift_ffi11SwiftObjectC5valueSivs"(i64 %0, ptr swiftself %1) #0 {
entry:
  %access-scratch = alloca [24 x i8], align 8
  %2 = getelementptr inbounds %T18red_team_swift_ffi11SwiftObjectC, ptr %1, i32 0, i32 1
  call void @llvm.lifetime.start.p0(i64 -1, ptr %access-scratch)
  call void @swift_beginAccess(ptr %2, ptr %access-scratch, i64 33, ptr null) #3
  %._value = getelementptr inbounds %TSi, ptr %2, i32 0, i32 0
  store i64 %0, ptr %._value, align 8
  call void @swift_endAccess(ptr %access-scratch) #3
  call void @llvm.lifetime.end.p0(i64 -1, ptr %access-scratch)
  ret void
}

; Function Attrs: noinline
define hidden swiftcc { ptr, ptr } @"$s18red_team_swift_ffi11SwiftObjectC5valueSivM"(ptr noalias dereferenceable(32) %0, ptr swiftself %1) #1 {
entry:
  %access-scratch = getelementptr inbounds %"$s18red_team_swift_ffi11SwiftObjectC5valueSivM.Frame", ptr %0, i32 0, i32 0
  %2 = getelementptr inbounds %T18red_team_swift_ffi11SwiftObjectC, ptr %1, i32 0, i32 1
  call void @llvm.lifetime.start.p0(i64 -1, ptr %access-scratch)
  call void @swift_beginAccess(ptr %2, ptr %access-scratch, i64 33, ptr null) #3
  %3 = insertvalue { ptr, ptr } poison, ptr @"$s18red_team_swift_ffi11SwiftObjectC5valueSivM.resume.0", 0
  %4 = insertvalue { ptr, ptr } %3, ptr %2, 1
  ret { ptr, ptr } %4
}

define internal swiftcc void @"$s18red_team_swift_ffi11SwiftObjectC5valueSivM.resume.0"(ptr noalias noundef nonnull align 8 dereferenceable(32) %0, i1 %1) #0 {
entryresume.0:
  %access-scratch = getelementptr inbounds %"$s18red_team_swift_ffi11SwiftObjectC5valueSivM.Frame", ptr %0, i32 0, i32 0
  br i1 %1, label %3, label %2

2:                                                ; preds = %entryresume.0
  call void @swift_endAccess(ptr %access-scratch) #3
  call void @llvm.lifetime.end.p0(i64 -1, ptr %access-scratch)
  br label %CoroEnd

3:                                                ; preds = %entryresume.0
  call void @swift_endAccess(ptr %access-scratch) #3
  call void @llvm.lifetime.end.p0(i64 -1, ptr %access-scratch)
  br label %CoroEnd

CoroEnd:                                          ; preds = %2, %3
  ret void
}

define hidden swiftcc ptr @"$s18red_team_swift_ffi11SwiftObjectCfd"(ptr swiftself %0) #0 {
entry:
  %self.debug = alloca ptr, align 8
  call void @llvm.memset.p0.i64(ptr align 8 %self.debug, i8 0, i64 8, i1 false)
  store ptr %0, ptr %self.debug, align 8
  %1 = call swiftcc { ptr, ptr } @"$ss27_allocateUninitializedArrayySayxG_BptBwlF"(i64 1, ptr getelementptr inbounds (%swift.full_existential_type, ptr @"$sypN", i32 0, i32 1))
  %2 = extractvalue { ptr, ptr } %1, 0
  %3 = extractvalue { ptr, ptr } %1, 1
  %4 = call swiftcc { i64, ptr } @"$sSS21_builtinStringLiteral17utf8CodeUnitCount7isASCIISSBp_BwBi1_tcfC"(ptr @".str.23.SwiftObject deallocated", i64 23, i1 true)
  %5 = extractvalue { i64, ptr } %4, 0
  %6 = extractvalue { i64, ptr } %4, 1
  %7 = getelementptr inbounds %Any, ptr %3, i32 0, i32 1
  store ptr @"$sSSN", ptr %7, align 8
  %8 = getelementptr inbounds %Any, ptr %3, i32 0, i32 0
  %9 = getelementptr inbounds %Any, ptr %3, i32 0, i32 0
  %._guts = getelementptr inbounds %TSS, ptr %9, i32 0, i32 0
  %._guts._object = getelementptr inbounds %Ts11_StringGutsV, ptr %._guts, i32 0, i32 0
  %._guts._object._countAndFlagsBits = getelementptr inbounds %Ts13_StringObjectV, ptr %._guts._object, i32 0, i32 0
  %._guts._object._countAndFlagsBits._value = getelementptr inbounds %Ts6UInt64V, ptr %._guts._object._countAndFlagsBits, i32 0, i32 0
  store i64 %5, ptr %._guts._object._countAndFlagsBits._value, align 8
  %._guts._object._object = getelementptr inbounds %Ts13_StringObjectV, ptr %._guts._object, i32 0, i32 1
  store ptr %6, ptr %._guts._object._object, align 8
  %10 = call swiftcc ptr @"$ss27_finalizeUninitializedArrayySayxGABnlF"(ptr %2, ptr getelementptr inbounds (%swift.full_existential_type, ptr @"$sypN", i32 0, i32 1))
  %11 = call swiftcc { i64, ptr } @"$ss5print_9separator10terminatoryypd_S2StFfA0_"()
  %12 = extractvalue { i64, ptr } %11, 0
  %13 = extractvalue { i64, ptr } %11, 1
  %14 = call swiftcc { i64, ptr } @"$ss5print_9separator10terminatoryypd_S2StFfA1_"()
  %15 = extractvalue { i64, ptr } %14, 0
  %16 = extractvalue { i64, ptr } %14, 1
  call swiftcc void @"$ss5print_9separator10terminatoryypd_S2StF"(ptr %10, i64 %12, ptr %13, i64 %15, ptr %16)
  call void @swift_bridgeObjectRelease(ptr %16) #3
  call void @swift_bridgeObjectRelease(ptr %13) #3
  call void @swift_bridgeObjectRelease(ptr %10) #3
  ret ptr %0
}

define linkonce_odr hidden swiftcc ptr @"$ss27_finalizeUninitializedArrayySayxGABnlF"(ptr %0, ptr %Element) #0 {
entry:
  %Element1 = alloca ptr, align 8
  %1 = alloca %TSa, align 8
  store ptr %Element, ptr %Element1, align 8
  call void @llvm.lifetime.start.p0(i64 8, ptr %1)
  %._buffer = getelementptr inbounds %TSa, ptr %1, i32 0, i32 0
  %._buffer._storage = getelementptr inbounds %Ts12_ArrayBufferV, ptr %._buffer, i32 0, i32 0
  %._buffer._storage.rawValue = getelementptr inbounds %Ts14_BridgeStorageV, ptr %._buffer._storage, i32 0, i32 0
  store ptr %0, ptr %._buffer._storage.rawValue, align 8
  %2 = call swiftcc %swift.metadata_response @"$sSaMa"(i64 0, ptr %Element) #14
  %3 = extractvalue %swift.metadata_response %2, 0
  call swiftcc void @"$sSa12_endMutationyyF"(ptr %3, ptr nocapture swiftself dereferenceable(8) %1)
  %._buffer2 = getelementptr inbounds %TSa, ptr %1, i32 0, i32 0
  %._buffer2._storage = getelementptr inbounds %Ts12_ArrayBufferV, ptr %._buffer2, i32 0, i32 0
  %._buffer2._storage.rawValue = getelementptr inbounds %Ts14_BridgeStorageV, ptr %._buffer2._storage, i32 0, i32 0
  %4 = load ptr, ptr %._buffer2._storage.rawValue, align 8
  call void @llvm.lifetime.end.p0(i64 8, ptr %1)
  ret ptr %4
}

define linkonce_odr hidden swiftcc { i64, ptr } @"$ss5print_9separator10terminatoryypd_S2StFfA0_"() #0 {
entry:
  %0 = call swiftcc { i64, ptr } @"$sSS21_builtinStringLiteral17utf8CodeUnitCount7isASCIISSBp_BwBi1_tcfC"(ptr @".str.1. ", i64 1, i1 true)
  %1 = extractvalue { i64, ptr } %0, 0
  %2 = extractvalue { i64, ptr } %0, 1
  %3 = insertvalue { i64, ptr } undef, i64 %1, 0
  %4 = insertvalue { i64, ptr } %3, ptr %2, 1
  ret { i64, ptr } %4
}

define linkonce_odr hidden swiftcc { i64, ptr } @"$ss5print_9separator10terminatoryypd_S2StFfA1_"() #0 {
entry:
  %0 = call swiftcc { i64, ptr } @"$sSS21_builtinStringLiteral17utf8CodeUnitCount7isASCIISSBp_BwBi1_tcfC"(ptr @".str.1.\0A", i64 1, i1 true)
  %1 = extractvalue { i64, ptr } %0, 0
  %2 = extractvalue { i64, ptr } %0, 1
  %3 = insertvalue { i64, ptr } undef, i64 %1, 0
  %4 = insertvalue { i64, ptr } %3, ptr %2, 1
  ret { i64, ptr } %4
}

define hidden swiftcc void @"$s18red_team_swift_ffi11SwiftObjectCfD"(ptr swiftself %0) #0 {
entry:
  %self.debug = alloca ptr, align 8
  call void @llvm.memset.p0.i64(ptr align 8 %self.debug, i8 0, i64 8, i1 false)
  store ptr %0, ptr %self.debug, align 8
  %1 = call swiftcc ptr @"$s18red_team_swift_ffi11SwiftObjectCfd"(ptr swiftself %0)
  call void @swift_deallocClassInstance(ptr %1, i64 24, i64 7) #3
  ret void
}

define hidden swiftcc ptr @"$s18red_team_swift_ffi11SwiftObjectCACycfC"(ptr swiftself %0) #0 {
entry:
  %1 = call noalias ptr @swift_allocObject(ptr %0, i64 24, i64 7) #3
  %2 = call swiftcc ptr @"$s18red_team_swift_ffi11SwiftObjectCACycfc"(ptr swiftself %1)
  ret ptr %2
}

define hidden swiftcc ptr @"$s18red_team_swift_ffi11SwiftObjectCACycfc"(ptr swiftself %0) #0 {
entry:
  %self.debug = alloca ptr, align 8
  call void @llvm.memset.p0.i64(ptr align 8 %self.debug, i8 0, i64 8, i1 false)
  store ptr %0, ptr %self.debug, align 8
  %1 = getelementptr inbounds %T18red_team_swift_ffi11SwiftObjectC, ptr %0, i32 0, i32 1
  %._value = getelementptr inbounds %TSi, ptr %1, i32 0, i32 0
  store i64 42, ptr %._value, align 8
  ret ptr %0
}

define hidden swiftcc void @"$s18red_team_swift_ffi0C19_bug_01_unowned_uafyyF"() #0 {
entry:
  %0 = alloca %T18red_team_swift_ffi11SwiftObjectCSg, align 8
  %1 = alloca %swift.unowned, align 8
  %2 = alloca %Ts26DefaultStringInterpolationV, align 8
  %3 = alloca %TSi, align 8
  call void @llvm.lifetime.start.p0(i64 8, ptr %0)
  %4 = call swiftcc %swift.metadata_response @"$s18red_team_swift_ffi11SwiftObjectCMa"(i64 0) #14
  %5 = extractvalue %swift.metadata_response %4, 0
  %6 = call swiftcc ptr @"$s18red_team_swift_ffi11SwiftObjectCACycfC"(ptr swiftself %5)
  %7 = ptrtoint ptr %6 to i64
  %8 = inttoptr i64 %7 to ptr
  %9 = call ptr @swift_retain(ptr returned %8) #6
  store i64 %7, ptr %0, align 8
  call void @llvm.lifetime.start.p0(i64 8, ptr %1)
  %10 = call ptr @swift_unownedRetain(ptr returned %6) #3
  store ptr %6, ptr %1, align 8
  call void @swift_release(ptr %6) #3
  %11 = load i64, ptr %0, align 8
  store i64 0, ptr %0, align 8
  %12 = inttoptr i64 %11 to ptr
  call void @swift_release(ptr %12) #3
  %13 = call swiftcc { ptr, ptr } @"$ss27_allocateUninitializedArrayySayxG_BptBwlF"(i64 1, ptr getelementptr inbounds (%swift.full_existential_type, ptr @"$sypN", i32 0, i32 1))
  %14 = extractvalue { ptr, ptr } %13, 0
  %15 = extractvalue { ptr, ptr } %13, 1
  call void @llvm.lifetime.start.p0(i64 16, ptr %2)
  %16 = call swiftcc { i64, ptr } @"$ss26DefaultStringInterpolationV15literalCapacity18interpolationCountABSi_SitcfC"(i64 14, i64 1)
  %17 = extractvalue { i64, ptr } %16, 0
  %18 = extractvalue { i64, ptr } %16, 1
  %._storage = getelementptr inbounds %Ts26DefaultStringInterpolationV, ptr %2, i32 0, i32 0
  %._storage._guts = getelementptr inbounds %TSS, ptr %._storage, i32 0, i32 0
  %._storage._guts._object = getelementptr inbounds %Ts11_StringGutsV, ptr %._storage._guts, i32 0, i32 0
  %._storage._guts._object._countAndFlagsBits = getelementptr inbounds %Ts13_StringObjectV, ptr %._storage._guts._object, i32 0, i32 0
  %._storage._guts._object._countAndFlagsBits._value = getelementptr inbounds %Ts6UInt64V, ptr %._storage._guts._object._countAndFlagsBits, i32 0, i32 0
  store i64 %17, ptr %._storage._guts._object._countAndFlagsBits._value, align 8
  %._storage._guts._object._object = getelementptr inbounds %Ts13_StringObjectV, ptr %._storage._guts._object, i32 0, i32 1
  store ptr %18, ptr %._storage._guts._object._object, align 8
  %19 = call swiftcc { i64, ptr } @"$sSS21_builtinStringLiteral17utf8CodeUnitCount7isASCIISSBp_BwBi1_tcfC"(ptr @".str.14.SWIFT-BUG-01: ", i64 14, i1 true)
  %20 = extractvalue { i64, ptr } %19, 0
  %21 = extractvalue { i64, ptr } %19, 1
  call swiftcc void @"$ss26DefaultStringInterpolationV13appendLiteralyySSF"(i64 %20, ptr %21, ptr nocapture swiftself dereferenceable(16) %2)
  call void @swift_bridgeObjectRelease(ptr %21) #3
  %22 = load ptr, ptr %1, align 8
  %23 = call ptr @swift_unownedRetainStrong(ptr returned %22) #3
  %24 = load ptr, ptr %22, align 8
  %25 = getelementptr inbounds ptr, ptr %24, i64 11
  %26 = load ptr, ptr %25, align 8, !invariant.load !39
  %27 = call swiftcc i64 %26(ptr swiftself %22)
  call void @swift_release(ptr %22) #3
  call void @llvm.lifetime.start.p0(i64 8, ptr %3)
  %._value = getelementptr inbounds %TSi, ptr %3, i32 0, i32 0
  store i64 %27, ptr %._value, align 8
  call swiftcc void @"$ss26DefaultStringInterpolationV06appendC0yyxs06CustomB11ConvertibleRzlF"(ptr noalias %3, ptr @"$sSiN", ptr @"$sSis23CustomStringConvertiblesWP", ptr nocapture swiftself dereferenceable(16) %2)
  call void @llvm.lifetime.end.p0(i64 8, ptr %3)
  %28 = call swiftcc { i64, ptr } @"$sSS21_builtinStringLiteral17utf8CodeUnitCount7isASCIISSBp_BwBi1_tcfC"(ptr @.str.0., i64 0, i1 true)
  %29 = extractvalue { i64, ptr } %28, 0
  %30 = extractvalue { i64, ptr } %28, 1
  call swiftcc void @"$ss26DefaultStringInterpolationV13appendLiteralyySSF"(i64 %29, ptr %30, ptr nocapture swiftself dereferenceable(16) %2)
  call void @swift_bridgeObjectRelease(ptr %30) #3
  %._storage1 = getelementptr inbounds %Ts26DefaultStringInterpolationV, ptr %2, i32 0, i32 0
  %._storage1._guts = getelementptr inbounds %TSS, ptr %._storage1, i32 0, i32 0
  %._storage1._guts._object = getelementptr inbounds %Ts11_StringGutsV, ptr %._storage1._guts, i32 0, i32 0
  %._storage1._guts._object._countAndFlagsBits = getelementptr inbounds %Ts13_StringObjectV, ptr %._storage1._guts._object, i32 0, i32 0
  %._storage1._guts._object._countAndFlagsBits._value = getelementptr inbounds %Ts6UInt64V, ptr %._storage1._guts._object._countAndFlagsBits, i32 0, i32 0
  %31 = load i64, ptr %._storage1._guts._object._countAndFlagsBits._value, align 8
  %._storage1._guts._object._object = getelementptr inbounds %Ts13_StringObjectV, ptr %._storage1._guts._object, i32 0, i32 1
  %32 = load ptr, ptr %._storage1._guts._object._object, align 8
  %33 = call ptr @swift_bridgeObjectRetain(ptr returned %32) #3
  %34 = call ptr @"$ss26DefaultStringInterpolationVWOh"(ptr %2)
  call void @llvm.lifetime.end.p0(i64 16, ptr %2)
  %35 = call swiftcc { i64, ptr } @"$sSS19stringInterpolationSSs013DefaultStringB0V_tcfC"(i64 %31, ptr %32)
  %36 = extractvalue { i64, ptr } %35, 0
  %37 = extractvalue { i64, ptr } %35, 1
  %38 = getelementptr inbounds %Any, ptr %15, i32 0, i32 1
  store ptr @"$sSSN", ptr %38, align 8
  %39 = getelementptr inbounds %Any, ptr %15, i32 0, i32 0
  %40 = getelementptr inbounds %Any, ptr %15, i32 0, i32 0
  %._guts = getelementptr inbounds %TSS, ptr %40, i32 0, i32 0
  %._guts._object = getelementptr inbounds %Ts11_StringGutsV, ptr %._guts, i32 0, i32 0
  %._guts._object._countAndFlagsBits = getelementptr inbounds %Ts13_StringObjectV, ptr %._guts._object, i32 0, i32 0
  %._guts._object._countAndFlagsBits._value = getelementptr inbounds %Ts6UInt64V, ptr %._guts._object._countAndFlagsBits, i32 0, i32 0
  store i64 %36, ptr %._guts._object._countAndFlagsBits._value, align 8
  %._guts._object._object = getelementptr inbounds %Ts13_StringObjectV, ptr %._guts._object, i32 0, i32 1
  store ptr %37, ptr %._guts._object._object, align 8
  %41 = call swiftcc ptr @"$ss27_finalizeUninitializedArrayySayxGABnlF"(ptr %14, ptr getelementptr inbounds (%swift.full_existential_type, ptr @"$sypN", i32 0, i32 1))
  %42 = call swiftcc { i64, ptr } @"$ss5print_9separator10terminatoryypd_S2StFfA0_"()
  %43 = extractvalue { i64, ptr } %42, 0
  %44 = extractvalue { i64, ptr } %42, 1
  %45 = call swiftcc { i64, ptr } @"$ss5print_9separator10terminatoryypd_S2StFfA1_"()
  %46 = extractvalue { i64, ptr } %45, 0
  %47 = extractvalue { i64, ptr } %45, 1
  call swiftcc void @"$ss5print_9separator10terminatoryypd_S2StF"(ptr %41, i64 %43, ptr %44, i64 %46, ptr %47)
  call void @swift_bridgeObjectRelease(ptr %47) #3
  call void @swift_bridgeObjectRelease(ptr %44) #3
  call void @swift_bridgeObjectRelease(ptr %41) #3
  %toDestroy = load ptr, ptr %1, align 8
  call void @swift_unownedRelease(ptr %toDestroy) #3
  call void @llvm.lifetime.end.p0(i64 8, ptr %1)
  %48 = call ptr @"$s18red_team_swift_ffi11SwiftObjectCSgWOh"(ptr %0)
  call void @llvm.lifetime.end.p0(i64 8, ptr %0)
  ret void
}

define hidden swiftcc void @"$s18red_team_swift_ffi0C17_bug_02_weak_raceyyF"() #0 {
entry:
  %0 = alloca %T18red_team_swift_ffi11SwiftObjectCSg, align 8
  %1 = alloca %swift.weak, align 8
  %strong.debug = alloca ptr, align 8
  call void @llvm.memset.p0.i64(ptr align 8 %strong.debug, i8 0, i64 8, i1 false)
  %2 = alloca %Ts26DefaultStringInterpolationV, align 8
  %3 = alloca %TSi, align 8
  call void @llvm.lifetime.start.p0(i64 8, ptr %0)
  %4 = call swiftcc %swift.metadata_response @"$s18red_team_swift_ffi11SwiftObjectCMa"(i64 0) #14
  %5 = extractvalue %swift.metadata_response %4, 0
  %6 = call swiftcc ptr @"$s18red_team_swift_ffi11SwiftObjectCACycfC"(ptr swiftself %5)
  %7 = ptrtoint ptr %6 to i64
  %8 = inttoptr i64 %7 to ptr
  %9 = call ptr @swift_retain(ptr returned %8) #6
  store i64 %7, ptr %0, align 8
  call void @llvm.lifetime.start.p0(i64 8, ptr %1)
  %10 = inttoptr i64 %7 to ptr
  %11 = call ptr @swift_weakInit(ptr returned %1, ptr %10) #3
  %12 = inttoptr i64 %7 to ptr
  call void @swift_release(ptr %12) #3
  %13 = call ptr @swift_weakLoadStrong(ptr %1) #3
  %14 = ptrtoint ptr %13 to i64
  %15 = icmp eq i64 %14, 0
  br i1 %15, label %18, label %16

16:                                               ; preds = %entry
  %17 = inttoptr i64 %14 to ptr
  br label %19

18:                                               ; preds = %entry
  br label %54

19:                                               ; preds = %16
  %20 = phi ptr [ %17, %16 ]
  store ptr %20, ptr %strong.debug, align 8
  %21 = call swiftcc { ptr, ptr } @"$ss27_allocateUninitializedArrayySayxG_BptBwlF"(i64 1, ptr getelementptr inbounds (%swift.full_existential_type, ptr @"$sypN", i32 0, i32 1))
  %22 = extractvalue { ptr, ptr } %21, 0
  %23 = extractvalue { ptr, ptr } %21, 1
  call void @llvm.lifetime.start.p0(i64 16, ptr %2)
  %24 = call swiftcc { i64, ptr } @"$ss26DefaultStringInterpolationV15literalCapacity18interpolationCountABSi_SitcfC"(i64 14, i64 1)
  %25 = extractvalue { i64, ptr } %24, 0
  %26 = extractvalue { i64, ptr } %24, 1
  %._storage = getelementptr inbounds %Ts26DefaultStringInterpolationV, ptr %2, i32 0, i32 0
  %._storage._guts = getelementptr inbounds %TSS, ptr %._storage, i32 0, i32 0
  %._storage._guts._object = getelementptr inbounds %Ts11_StringGutsV, ptr %._storage._guts, i32 0, i32 0
  %._storage._guts._object._countAndFlagsBits = getelementptr inbounds %Ts13_StringObjectV, ptr %._storage._guts._object, i32 0, i32 0
  %._storage._guts._object._countAndFlagsBits._value = getelementptr inbounds %Ts6UInt64V, ptr %._storage._guts._object._countAndFlagsBits, i32 0, i32 0
  store i64 %25, ptr %._storage._guts._object._countAndFlagsBits._value, align 8
  %._storage._guts._object._object = getelementptr inbounds %Ts13_StringObjectV, ptr %._storage._guts._object, i32 0, i32 1
  store ptr %26, ptr %._storage._guts._object._object, align 8
  %27 = call swiftcc { i64, ptr } @"$sSS21_builtinStringLiteral17utf8CodeUnitCount7isASCIISSBp_BwBi1_tcfC"(ptr @".str.14.SWIFT-BUG-02: ", i64 14, i1 true)
  %28 = extractvalue { i64, ptr } %27, 0
  %29 = extractvalue { i64, ptr } %27, 1
  call swiftcc void @"$ss26DefaultStringInterpolationV13appendLiteralyySSF"(i64 %28, ptr %29, ptr nocapture swiftself dereferenceable(16) %2)
  call void @swift_bridgeObjectRelease(ptr %29) #3
  %30 = load ptr, ptr %20, align 8
  %31 = getelementptr inbounds ptr, ptr %30, i64 11
  %32 = load ptr, ptr %31, align 8, !invariant.load !39
  %33 = call swiftcc i64 %32(ptr swiftself %20)
  call void @llvm.lifetime.start.p0(i64 8, ptr %3)
  %._value = getelementptr inbounds %TSi, ptr %3, i32 0, i32 0
  store i64 %33, ptr %._value, align 8
  call swiftcc void @"$ss26DefaultStringInterpolationV06appendC0yyxs06CustomB11ConvertibleRzlF"(ptr noalias %3, ptr @"$sSiN", ptr @"$sSis23CustomStringConvertiblesWP", ptr nocapture swiftself dereferenceable(16) %2)
  call void @llvm.lifetime.end.p0(i64 8, ptr %3)
  %34 = call swiftcc { i64, ptr } @"$sSS21_builtinStringLiteral17utf8CodeUnitCount7isASCIISSBp_BwBi1_tcfC"(ptr @.str.0., i64 0, i1 true)
  %35 = extractvalue { i64, ptr } %34, 0
  %36 = extractvalue { i64, ptr } %34, 1
  call swiftcc void @"$ss26DefaultStringInterpolationV13appendLiteralyySSF"(i64 %35, ptr %36, ptr nocapture swiftself dereferenceable(16) %2)
  call void @swift_bridgeObjectRelease(ptr %36) #3
  %._storage1 = getelementptr inbounds %Ts26DefaultStringInterpolationV, ptr %2, i32 0, i32 0
  %._storage1._guts = getelementptr inbounds %TSS, ptr %._storage1, i32 0, i32 0
  %._storage1._guts._object = getelementptr inbounds %Ts11_StringGutsV, ptr %._storage1._guts, i32 0, i32 0
  %._storage1._guts._object._countAndFlagsBits = getelementptr inbounds %Ts13_StringObjectV, ptr %._storage1._guts._object, i32 0, i32 0
  %._storage1._guts._object._countAndFlagsBits._value = getelementptr inbounds %Ts6UInt64V, ptr %._storage1._guts._object._countAndFlagsBits, i32 0, i32 0
  %37 = load i64, ptr %._storage1._guts._object._countAndFlagsBits._value, align 8
  %._storage1._guts._object._object = getelementptr inbounds %Ts13_StringObjectV, ptr %._storage1._guts._object, i32 0, i32 1
  %38 = load ptr, ptr %._storage1._guts._object._object, align 8
  %39 = call ptr @swift_bridgeObjectRetain(ptr returned %38) #3
  %40 = call ptr @"$ss26DefaultStringInterpolationVWOh"(ptr %2)
  call void @llvm.lifetime.end.p0(i64 16, ptr %2)
  %41 = call swiftcc { i64, ptr } @"$sSS19stringInterpolationSSs013DefaultStringB0V_tcfC"(i64 %37, ptr %38)
  %42 = extractvalue { i64, ptr } %41, 0
  %43 = extractvalue { i64, ptr } %41, 1
  %44 = getelementptr inbounds %Any, ptr %23, i32 0, i32 1
  store ptr @"$sSSN", ptr %44, align 8
  %45 = getelementptr inbounds %Any, ptr %23, i32 0, i32 0
  %46 = getelementptr inbounds %Any, ptr %23, i32 0, i32 0
  %._guts = getelementptr inbounds %TSS, ptr %46, i32 0, i32 0
  %._guts._object = getelementptr inbounds %Ts11_StringGutsV, ptr %._guts, i32 0, i32 0
  %._guts._object._countAndFlagsBits = getelementptr inbounds %Ts13_StringObjectV, ptr %._guts._object, i32 0, i32 0
  %._guts._object._countAndFlagsBits._value = getelementptr inbounds %Ts6UInt64V, ptr %._guts._object._countAndFlagsBits, i32 0, i32 0
  store i64 %42, ptr %._guts._object._countAndFlagsBits._value, align 8
  %._guts._object._object = getelementptr inbounds %Ts13_StringObjectV, ptr %._guts._object, i32 0, i32 1
  store ptr %43, ptr %._guts._object._object, align 8
  %47 = call swiftcc ptr @"$ss27_finalizeUninitializedArrayySayxGABnlF"(ptr %22, ptr getelementptr inbounds (%swift.full_existential_type, ptr @"$sypN", i32 0, i32 1))
  %48 = call swiftcc { i64, ptr } @"$ss5print_9separator10terminatoryypd_S2StFfA0_"()
  %49 = extractvalue { i64, ptr } %48, 0
  %50 = extractvalue { i64, ptr } %48, 1
  %51 = call swiftcc { i64, ptr } @"$ss5print_9separator10terminatoryypd_S2StFfA1_"()
  %52 = extractvalue { i64, ptr } %51, 0
  %53 = extractvalue { i64, ptr } %51, 1
  call swiftcc void @"$ss5print_9separator10terminatoryypd_S2StF"(ptr %47, i64 %49, ptr %50, i64 %52, ptr %53)
  call void @swift_bridgeObjectRelease(ptr %53) #3
  call void @swift_bridgeObjectRelease(ptr %50) #3
  call void @swift_bridgeObjectRelease(ptr %47) #3
  call void @swift_release(ptr %20) #3
  br label %54

54:                                               ; preds = %19, %18
  %55 = load i64, ptr %0, align 8
  store i64 0, ptr %0, align 8
  %56 = inttoptr i64 %55 to ptr
  call void @swift_release(ptr %56) #3
  call void @swift_weakDestroy(ptr %1) #3
  call void @llvm.lifetime.end.p0(i64 8, ptr %1)
  %57 = call ptr @"$s18red_team_swift_ffi11SwiftObjectCSgWOh"(ptr %0)
  call void @llvm.lifetime.end.p0(i64 8, ptr %0)
  ret void
}

define hidden swiftcc void @"$s18red_team_swift_ffi0C19_bug_03_raw_ptr_uafyyF"() #0 {
entry:
  %ptr.debug = alloca ptr, align 8
  call void @llvm.memset.p0.i64(ptr align 8 %ptr.debug, i8 0, i64 8, i1 false)
  %buf.debug = alloca ptr, align 8
  call void @llvm.memset.p0.i64(ptr align 8 %buf.debug, i8 0, i64 8, i1 false)
  %0 = alloca %Ts5UInt8V, align 1
  %data.debug = alloca i8, align 8
  call void @llvm.memset.p0.i64(ptr align 8 %data.debug, i8 0, i64 1, i1 false)
  %1 = alloca %Ts26DefaultStringInterpolationV, align 8
  %2 = alloca %Ts5UInt8V, align 1
  %3 = call ptr @c_ffi_alloc(i32 128)
  %4 = ptrtoint ptr %3 to i64
  %5 = icmp eq i64 %4, 0
  br i1 %5, label %8, label %6

6:                                                ; preds = %entry
  %7 = inttoptr i64 %4 to ptr
  br label %9

8:                                                ; preds = %entry
  call swiftcc void @"$ss17_assertionFailure__4file4line5flagss5NeverOs12StaticStringV_A2HSus6UInt32VtF"(i64 ptrtoint (ptr @".str.11.Fatal error" to i64), i64 11, i8 2, i64 ptrtoint (ptr @".str.57.Unexpectedly found nil while unwrapping an Optional value" to i64), i64 57, i8 2, i64 ptrtoint (ptr @".str.43.red_team_swift_ffi/red_team_swift_ffi.swift" to i64), i64 43, i8 2, i64 80, i32 1)
  unreachable

9:                                                ; preds = %6
  %10 = phi ptr [ %7, %6 ]
  store ptr %10, ptr %ptr.debug, align 8
  store ptr %10, ptr %buf.debug, align 8
  %._value = getelementptr inbounds %Ts5UInt8V, ptr %10, i32 0, i32 0
  store i8 65, ptr %._value, align 1
  %11 = ptrtoint ptr %10 to i64
  %12 = inttoptr i64 %11 to ptr
  call void @c_ffi_free(ptr %12)
  call void @llvm.lifetime.start.p0(i64 1, ptr %0)
  %13 = call swiftcc i64 @"$sSv4load14fromByteOffset2asxSi_xmtlFfA_"(ptr @"$ss5UInt8VN")
  call swiftcc void @"$sSv4load14fromByteOffset2asxSi_xmtlF"(ptr noalias sret(%swift.opaque) %0, i64 %13, ptr @"$ss5UInt8VN", ptr %10, ptr @"$ss5UInt8VN")
  %._value1 = getelementptr inbounds %Ts5UInt8V, ptr %0, i32 0, i32 0
  %14 = load i8, ptr %._value1, align 1
  store i8 %14, ptr %data.debug, align 8
  call void @llvm.lifetime.end.p0(i64 1, ptr %0)
  %15 = call swiftcc { ptr, ptr } @"$ss27_allocateUninitializedArrayySayxG_BptBwlF"(i64 1, ptr getelementptr inbounds (%swift.full_existential_type, ptr @"$sypN", i32 0, i32 1))
  %16 = extractvalue { ptr, ptr } %15, 0
  %17 = extractvalue { ptr, ptr } %15, 1
  call void @llvm.lifetime.start.p0(i64 16, ptr %1)
  %18 = call swiftcc { i64, ptr } @"$ss26DefaultStringInterpolationV15literalCapacity18interpolationCountABSi_SitcfC"(i64 14, i64 1)
  %19 = extractvalue { i64, ptr } %18, 0
  %20 = extractvalue { i64, ptr } %18, 1
  %._storage = getelementptr inbounds %Ts26DefaultStringInterpolationV, ptr %1, i32 0, i32 0
  %._storage._guts = getelementptr inbounds %TSS, ptr %._storage, i32 0, i32 0
  %._storage._guts._object = getelementptr inbounds %Ts11_StringGutsV, ptr %._storage._guts, i32 0, i32 0
  %._storage._guts._object._countAndFlagsBits = getelementptr inbounds %Ts13_StringObjectV, ptr %._storage._guts._object, i32 0, i32 0
  %._storage._guts._object._countAndFlagsBits._value = getelementptr inbounds %Ts6UInt64V, ptr %._storage._guts._object._countAndFlagsBits, i32 0, i32 0
  store i64 %19, ptr %._storage._guts._object._countAndFlagsBits._value, align 8
  %._storage._guts._object._object = getelementptr inbounds %Ts13_StringObjectV, ptr %._storage._guts._object, i32 0, i32 1
  store ptr %20, ptr %._storage._guts._object._object, align 8
  %21 = call swiftcc { i64, ptr } @"$sSS21_builtinStringLiteral17utf8CodeUnitCount7isASCIISSBp_BwBi1_tcfC"(ptr @".str.14.SWIFT-BUG-03: ", i64 14, i1 true)
  %22 = extractvalue { i64, ptr } %21, 0
  %23 = extractvalue { i64, ptr } %21, 1
  call swiftcc void @"$ss26DefaultStringInterpolationV13appendLiteralyySSF"(i64 %22, ptr %23, ptr nocapture swiftself dereferenceable(16) %1)
  call void @swift_bridgeObjectRelease(ptr %23) #3
  call void @llvm.lifetime.start.p0(i64 1, ptr %2)
  %._value2 = getelementptr inbounds %Ts5UInt8V, ptr %2, i32 0, i32 0
  store i8 %14, ptr %._value2, align 1
  call swiftcc void @"$ss26DefaultStringInterpolationV06appendC0yyxs06CustomB11ConvertibleRzlF"(ptr noalias %2, ptr @"$ss5UInt8VN", ptr @"$ss5UInt8Vs23CustomStringConvertiblesWP", ptr nocapture swiftself dereferenceable(16) %1)
  call void @llvm.lifetime.end.p0(i64 1, ptr %2)
  %24 = call swiftcc { i64, ptr } @"$sSS21_builtinStringLiteral17utf8CodeUnitCount7isASCIISSBp_BwBi1_tcfC"(ptr @.str.0., i64 0, i1 true)
  %25 = extractvalue { i64, ptr } %24, 0
  %26 = extractvalue { i64, ptr } %24, 1
  call swiftcc void @"$ss26DefaultStringInterpolationV13appendLiteralyySSF"(i64 %25, ptr %26, ptr nocapture swiftself dereferenceable(16) %1)
  call void @swift_bridgeObjectRelease(ptr %26) #3
  %._storage3 = getelementptr inbounds %Ts26DefaultStringInterpolationV, ptr %1, i32 0, i32 0
  %._storage3._guts = getelementptr inbounds %TSS, ptr %._storage3, i32 0, i32 0
  %._storage3._guts._object = getelementptr inbounds %Ts11_StringGutsV, ptr %._storage3._guts, i32 0, i32 0
  %._storage3._guts._object._countAndFlagsBits = getelementptr inbounds %Ts13_StringObjectV, ptr %._storage3._guts._object, i32 0, i32 0
  %._storage3._guts._object._countAndFlagsBits._value = getelementptr inbounds %Ts6UInt64V, ptr %._storage3._guts._object._countAndFlagsBits, i32 0, i32 0
  %27 = load i64, ptr %._storage3._guts._object._countAndFlagsBits._value, align 8
  %._storage3._guts._object._object = getelementptr inbounds %Ts13_StringObjectV, ptr %._storage3._guts._object, i32 0, i32 1
  %28 = load ptr, ptr %._storage3._guts._object._object, align 8
  %29 = call ptr @swift_bridgeObjectRetain(ptr returned %28) #3
  %30 = call ptr @"$ss26DefaultStringInterpolationVWOh"(ptr %1)
  call void @llvm.lifetime.end.p0(i64 16, ptr %1)
  %31 = call swiftcc { i64, ptr } @"$sSS19stringInterpolationSSs013DefaultStringB0V_tcfC"(i64 %27, ptr %28)
  %32 = extractvalue { i64, ptr } %31, 0
  %33 = extractvalue { i64, ptr } %31, 1
  %34 = getelementptr inbounds %Any, ptr %17, i32 0, i32 1
  store ptr @"$sSSN", ptr %34, align 8
  %35 = getelementptr inbounds %Any, ptr %17, i32 0, i32 0
  %36 = getelementptr inbounds %Any, ptr %17, i32 0, i32 0
  %._guts = getelementptr inbounds %TSS, ptr %36, i32 0, i32 0
  %._guts._object = getelementptr inbounds %Ts11_StringGutsV, ptr %._guts, i32 0, i32 0
  %._guts._object._countAndFlagsBits = getelementptr inbounds %Ts13_StringObjectV, ptr %._guts._object, i32 0, i32 0
  %._guts._object._countAndFlagsBits._value = getelementptr inbounds %Ts6UInt64V, ptr %._guts._object._countAndFlagsBits, i32 0, i32 0
  store i64 %32, ptr %._guts._object._countAndFlagsBits._value, align 8
  %._guts._object._object = getelementptr inbounds %Ts13_StringObjectV, ptr %._guts._object, i32 0, i32 1
  store ptr %33, ptr %._guts._object._object, align 8
  %37 = call swiftcc ptr @"$ss27_finalizeUninitializedArrayySayxGABnlF"(ptr %16, ptr getelementptr inbounds (%swift.full_existential_type, ptr @"$sypN", i32 0, i32 1))
  %38 = call swiftcc { i64, ptr } @"$ss5print_9separator10terminatoryypd_S2StFfA0_"()
  %39 = extractvalue { i64, ptr } %38, 0
  %40 = extractvalue { i64, ptr } %38, 1
  %41 = call swiftcc { i64, ptr } @"$ss5print_9separator10terminatoryypd_S2StFfA1_"()
  %42 = extractvalue { i64, ptr } %41, 0
  %43 = extractvalue { i64, ptr } %41, 1
  call swiftcc void @"$ss5print_9separator10terminatoryypd_S2StF"(ptr %37, i64 %39, ptr %40, i64 %42, ptr %43)
  call void @swift_bridgeObjectRelease(ptr %43) #3
  call void @swift_bridgeObjectRelease(ptr %40) #3
  call void @swift_bridgeObjectRelease(ptr %37) #3
  ret void
}

define linkonce_odr hidden swiftcc i64 @"$sSv4load14fromByteOffset2asxSi_xmtlFfA_"(ptr %T) #0 {
entry:
  %T1 = alloca ptr, align 8
  store ptr %T, ptr %T1, align 8
  ret i64 0
}

define hidden swiftcc void @"$s18red_team_swift_ffi0C27_bug_04_bridge_over_releaseyyF"() #0 {
entry:
  %nsStr.debug = alloca ptr, align 8
  call void @llvm.memset.p0.i64(ptr align 8 %nsStr.debug, i8 0, i64 8, i1 false)
  %swiftStr.debug = alloca %TSS, align 8
  call void @llvm.memset.p0.i64(ptr align 8 %swiftStr.debug, i8 0, i64 16, i1 false)
  %unmanaged.debug = alloca ptr, align 8
  call void @llvm.memset.p0.i64(ptr align 8 %unmanaged.debug, i8 0, i64 8, i1 false)
  %0 = alloca %Ts26DefaultStringInterpolationV, align 8
  %1 = alloca %TSS, align 8
  %2 = call swiftcc %swift.metadata_response @"$sSo8NSStringCMa"(i64 0) #14
  %3 = extractvalue %swift.metadata_response %2, 0
  %4 = call swiftcc ptr @"$sSo8NSStringC10FoundationE13stringLiteralABs12StaticStringV_tcfC"(i64 ptrtoint (ptr @".str.14.bridged string" to i64), i64 14, i8 2, ptr swiftself %3)
  store ptr %4, ptr %nsStr.debug, align 8
  %5 = call ptr @llvm.objc.retain(ptr %4)
  %6 = ptrtoint ptr %4 to i64
  %7 = call swiftcc { i64, ptr } @"$sSS10FoundationE36_unconditionallyBridgeFromObjectiveCySSSo8NSStringCSgFZ"(i64 %6)
  %8 = extractvalue { i64, ptr } %7, 0
  %9 = extractvalue { i64, ptr } %7, 1
  call void @llvm.lifetime.start.p0(i64 16, ptr %swiftStr.debug)
  %swiftStr.debug._guts = getelementptr inbounds %TSS, ptr %swiftStr.debug, i32 0, i32 0
  %swiftStr.debug._guts._object = getelementptr inbounds %Ts11_StringGutsV, ptr %swiftStr.debug._guts, i32 0, i32 0
  %swiftStr.debug._guts._object._countAndFlagsBits = getelementptr inbounds %Ts13_StringObjectV, ptr %swiftStr.debug._guts._object, i32 0, i32 0
  %swiftStr.debug._guts._object._countAndFlagsBits._value = getelementptr inbounds %Ts6UInt64V, ptr %swiftStr.debug._guts._object._countAndFlagsBits, i32 0, i32 0
  store i64 %8, ptr %swiftStr.debug._guts._object._countAndFlagsBits._value, align 8
  %swiftStr.debug._guts._object._object = getelementptr inbounds %Ts13_StringObjectV, ptr %swiftStr.debug._guts._object, i32 0, i32 1
  store ptr %9, ptr %swiftStr.debug._guts._object._object, align 8
  %10 = inttoptr i64 %6 to ptr
  call void @llvm.objc.release(ptr %10)
  %11 = call ptr @llvm.objc.retain(ptr %4)
  call void @swift_unknownObjectRelease(ptr %4) #3
  store ptr %4, ptr %unmanaged.debug, align 8
  %12 = call swiftcc { ptr, ptr } @"$ss27_allocateUninitializedArrayySayxG_BptBwlF"(i64 1, ptr getelementptr inbounds (%swift.full_existential_type, ptr @"$sypN", i32 0, i32 1))
  %13 = extractvalue { ptr, ptr } %12, 0
  %14 = extractvalue { ptr, ptr } %12, 1
  call void @llvm.lifetime.start.p0(i64 16, ptr %0)
  %15 = call swiftcc { i64, ptr } @"$ss26DefaultStringInterpolationV15literalCapacity18interpolationCountABSi_SitcfC"(i64 14, i64 1)
  %16 = extractvalue { i64, ptr } %15, 0
  %17 = extractvalue { i64, ptr } %15, 1
  %._storage = getelementptr inbounds %Ts26DefaultStringInterpolationV, ptr %0, i32 0, i32 0
  %._storage._guts = getelementptr inbounds %TSS, ptr %._storage, i32 0, i32 0
  %._storage._guts._object = getelementptr inbounds %Ts11_StringGutsV, ptr %._storage._guts, i32 0, i32 0
  %._storage._guts._object._countAndFlagsBits = getelementptr inbounds %Ts13_StringObjectV, ptr %._storage._guts._object, i32 0, i32 0
  %._storage._guts._object._countAndFlagsBits._value = getelementptr inbounds %Ts6UInt64V, ptr %._storage._guts._object._countAndFlagsBits, i32 0, i32 0
  store i64 %16, ptr %._storage._guts._object._countAndFlagsBits._value, align 8
  %._storage._guts._object._object = getelementptr inbounds %Ts13_StringObjectV, ptr %._storage._guts._object, i32 0, i32 1
  store ptr %17, ptr %._storage._guts._object._object, align 8
  %18 = call swiftcc { i64, ptr } @"$sSS21_builtinStringLiteral17utf8CodeUnitCount7isASCIISSBp_BwBi1_tcfC"(ptr @".str.14.SWIFT-BUG-04: ", i64 14, i1 true)
  %19 = extractvalue { i64, ptr } %18, 0
  %20 = extractvalue { i64, ptr } %18, 1
  call swiftcc void @"$ss26DefaultStringInterpolationV13appendLiteralyySSF"(i64 %19, ptr %20, ptr nocapture swiftself dereferenceable(16) %0)
  call void @swift_bridgeObjectRelease(ptr %20) #3
  call void @llvm.lifetime.start.p0(i64 16, ptr %1)
  %._guts = getelementptr inbounds %TSS, ptr %1, i32 0, i32 0
  %._guts._object = getelementptr inbounds %Ts11_StringGutsV, ptr %._guts, i32 0, i32 0
  %._guts._object._countAndFlagsBits = getelementptr inbounds %Ts13_StringObjectV, ptr %._guts._object, i32 0, i32 0
  %._guts._object._countAndFlagsBits._value = getelementptr inbounds %Ts6UInt64V, ptr %._guts._object._countAndFlagsBits, i32 0, i32 0
  store i64 %8, ptr %._guts._object._countAndFlagsBits._value, align 8
  %._guts._object._object = getelementptr inbounds %Ts13_StringObjectV, ptr %._guts._object, i32 0, i32 1
  store ptr %9, ptr %._guts._object._object, align 8
  call swiftcc void @"$ss26DefaultStringInterpolationV06appendC0yyxs06CustomB11ConvertibleRzs20TextOutputStreamableRzlF"(ptr noalias %1, ptr @"$sSSN", ptr @"$sSSs23CustomStringConvertiblesWP", ptr @"$sSSs20TextOutputStreamablesWP", ptr nocapture swiftself dereferenceable(16) %0)
  call void @llvm.lifetime.end.p0(i64 16, ptr %1)
  %21 = call swiftcc { i64, ptr } @"$sSS21_builtinStringLiteral17utf8CodeUnitCount7isASCIISSBp_BwBi1_tcfC"(ptr @.str.0., i64 0, i1 true)
  %22 = extractvalue { i64, ptr } %21, 0
  %23 = extractvalue { i64, ptr } %21, 1
  call swiftcc void @"$ss26DefaultStringInterpolationV13appendLiteralyySSF"(i64 %22, ptr %23, ptr nocapture swiftself dereferenceable(16) %0)
  call void @swift_bridgeObjectRelease(ptr %23) #3
  %._storage1 = getelementptr inbounds %Ts26DefaultStringInterpolationV, ptr %0, i32 0, i32 0
  %._storage1._guts = getelementptr inbounds %TSS, ptr %._storage1, i32 0, i32 0
  %._storage1._guts._object = getelementptr inbounds %Ts11_StringGutsV, ptr %._storage1._guts, i32 0, i32 0
  %._storage1._guts._object._countAndFlagsBits = getelementptr inbounds %Ts13_StringObjectV, ptr %._storage1._guts._object, i32 0, i32 0
  %._storage1._guts._object._countAndFlagsBits._value = getelementptr inbounds %Ts6UInt64V, ptr %._storage1._guts._object._countAndFlagsBits, i32 0, i32 0
  %24 = load i64, ptr %._storage1._guts._object._countAndFlagsBits._value, align 8
  %._storage1._guts._object._object = getelementptr inbounds %Ts13_StringObjectV, ptr %._storage1._guts._object, i32 0, i32 1
  %25 = load ptr, ptr %._storage1._guts._object._object, align 8
  %26 = call ptr @swift_bridgeObjectRetain(ptr returned %25) #3
  %27 = call ptr @"$ss26DefaultStringInterpolationVWOh"(ptr %0)
  call void @llvm.lifetime.end.p0(i64 16, ptr %0)
  %28 = call swiftcc { i64, ptr } @"$sSS19stringInterpolationSSs013DefaultStringB0V_tcfC"(i64 %24, ptr %25)
  %29 = extractvalue { i64, ptr } %28, 0
  %30 = extractvalue { i64, ptr } %28, 1
  %31 = getelementptr inbounds %Any, ptr %14, i32 0, i32 1
  store ptr @"$sSSN", ptr %31, align 8
  %32 = getelementptr inbounds %Any, ptr %14, i32 0, i32 0
  %33 = getelementptr inbounds %Any, ptr %14, i32 0, i32 0
  %._guts2 = getelementptr inbounds %TSS, ptr %33, i32 0, i32 0
  %._guts2._object = getelementptr inbounds %Ts11_StringGutsV, ptr %._guts2, i32 0, i32 0
  %._guts2._object._countAndFlagsBits = getelementptr inbounds %Ts13_StringObjectV, ptr %._guts2._object, i32 0, i32 0
  %._guts2._object._countAndFlagsBits._value = getelementptr inbounds %Ts6UInt64V, ptr %._guts2._object._countAndFlagsBits, i32 0, i32 0
  store i64 %29, ptr %._guts2._object._countAndFlagsBits._value, align 8
  %._guts2._object._object = getelementptr inbounds %Ts13_StringObjectV, ptr %._guts2._object, i32 0, i32 1
  store ptr %30, ptr %._guts2._object._object, align 8
  %34 = call swiftcc ptr @"$ss27_finalizeUninitializedArrayySayxGABnlF"(ptr %13, ptr getelementptr inbounds (%swift.full_existential_type, ptr @"$sypN", i32 0, i32 1))
  %35 = call swiftcc { i64, ptr } @"$ss5print_9separator10terminatoryypd_S2StFfA0_"()
  %36 = extractvalue { i64, ptr } %35, 0
  %37 = extractvalue { i64, ptr } %35, 1
  %38 = call swiftcc { i64, ptr } @"$ss5print_9separator10terminatoryypd_S2StFfA1_"()
  %39 = extractvalue { i64, ptr } %38, 0
  %40 = extractvalue { i64, ptr } %38, 1
  call swiftcc void @"$ss5print_9separator10terminatoryypd_S2StF"(ptr %34, i64 %36, ptr %37, i64 %39, ptr %40)
  call void @swift_bridgeObjectRelease(ptr %40) #3
  call void @swift_bridgeObjectRelease(ptr %37) #3
  call void @swift_bridgeObjectRelease(ptr %34) #3
  call void @swift_bridgeObjectRelease(ptr %9) #3
  call void @llvm.objc.release(ptr %4)
  ret void
}

define hidden swiftcc void @"$s18red_team_swift_ffi0C22_bug_05_pointer_escapeyyF"() #0 {
entry:
  %0 = alloca %TSa, align 8
  call void @llvm.memset.p0.i64(ptr align 8 %0, i8 0, i64 8, i1 false)
  %swifterror = alloca swifterror ptr, align 8
  store ptr null, ptr %swifterror, align 8
  %1 = alloca %Ts26DefaultStringInterpolationV, align 8
  %access-scratch = alloca [24 x i8], align 8
  %2 = alloca %Ts5UInt8V, align 1
  call void @llvm.lifetime.start.p0(i64 8, ptr %0)
  %3 = call swiftcc { ptr, ptr } @"$ss27_allocateUninitializedArrayySayxG_BptBwlF"(i64 5, ptr @"$ss5UInt8VN")
  %4 = extractvalue { ptr, ptr } %3, 0
  %5 = extractvalue { ptr, ptr } %3, 1
  %._value = getelementptr inbounds %Ts5UInt8V, ptr %5, i32 0, i32 0
  store i8 1, ptr %._value, align 1
  %6 = getelementptr inbounds %Ts5UInt8V, ptr %5, i64 1
  %._value1 = getelementptr inbounds %Ts5UInt8V, ptr %6, i32 0, i32 0
  store i8 2, ptr %._value1, align 1
  %7 = getelementptr inbounds %Ts5UInt8V, ptr %5, i64 2
  %._value2 = getelementptr inbounds %Ts5UInt8V, ptr %7, i32 0, i32 0
  store i8 3, ptr %._value2, align 1
  %8 = getelementptr inbounds %Ts5UInt8V, ptr %5, i64 3
  %._value3 = getelementptr inbounds %Ts5UInt8V, ptr %8, i32 0, i32 0
  store i8 4, ptr %._value3, align 1
  %9 = getelementptr inbounds %Ts5UInt8V, ptr %5, i64 4
  %._value4 = getelementptr inbounds %Ts5UInt8V, ptr %9, i32 0, i32 0
  store i8 5, ptr %._value4, align 1
  %10 = call swiftcc ptr @"$ss27_finalizeUninitializedArrayySayxGABnlF"(ptr %4, ptr @"$ss5UInt8VN")
  %._buffer = getelementptr inbounds %TSa, ptr %0, i32 0, i32 0
  %._buffer._storage = getelementptr inbounds %Ts12_ArrayBufferV, ptr %._buffer, i32 0, i32 0
  %._buffer._storage.rawValue = getelementptr inbounds %Ts14_BridgeStorageV, ptr %._buffer._storage, i32 0, i32 0
  store ptr %10, ptr %._buffer._storage.rawValue, align 8
  %11 = call ptr @__swift_instantiateConcreteTypeFromMangledNameV2(ptr @"$sSays5UInt8VGMd", ptr @"$sSays5UInt8VGMR") #12
  call swiftcc void @"$ss17withUnsafePointer2to_q0_xz_q0_SPyxGq_YKXEtq_YKs5ErrorR_Ri_zRi_0_r1_lF"(ptr noalias sret(%swift.opaque) undef, ptr %0, ptr @"$s18red_team_swift_ffi0C22_bug_05_pointer_escapeyyFySPySays5UInt8VGGXEfU_", ptr null, ptr %11, ptr @"$ss5NeverON", ptr getelementptr inbounds (%swift.full_existential_type, ptr @"$sytN", i32 0, i32 1), ptr @"$ss5NeverOs5ErrorsWP", ptr swiftself undef, ptr noalias nocapture swifterror dereferenceable(8) %swifterror, ptr undef)
  %12 = load ptr, ptr %swifterror, align 8
  %13 = icmp ne ptr %12, null
  %14 = ptrtoint ptr %12 to i64
  br i1 %13, label %54, label %15

15:                                               ; preds = %entry
  %16 = call swiftcc { ptr, ptr } @"$ss27_allocateUninitializedArrayySayxG_BptBwlF"(i64 1, ptr getelementptr inbounds (%swift.full_existential_type, ptr @"$sypN", i32 0, i32 1))
  %17 = extractvalue { ptr, ptr } %16, 0
  %18 = extractvalue { ptr, ptr } %16, 1
  call void @llvm.lifetime.start.p0(i64 16, ptr %1)
  %19 = call swiftcc { i64, ptr } @"$ss26DefaultStringInterpolationV15literalCapacity18interpolationCountABSi_SitcfC"(i64 14, i64 1)
  %20 = extractvalue { i64, ptr } %19, 0
  %21 = extractvalue { i64, ptr } %19, 1
  %._storage = getelementptr inbounds %Ts26DefaultStringInterpolationV, ptr %1, i32 0, i32 0
  %._storage._guts = getelementptr inbounds %TSS, ptr %._storage, i32 0, i32 0
  %._storage._guts._object = getelementptr inbounds %Ts11_StringGutsV, ptr %._storage._guts, i32 0, i32 0
  %._storage._guts._object._countAndFlagsBits = getelementptr inbounds %Ts13_StringObjectV, ptr %._storage._guts._object, i32 0, i32 0
  %._storage._guts._object._countAndFlagsBits._value = getelementptr inbounds %Ts6UInt64V, ptr %._storage._guts._object._countAndFlagsBits, i32 0, i32 0
  store i64 %20, ptr %._storage._guts._object._countAndFlagsBits._value, align 8
  %._storage._guts._object._object = getelementptr inbounds %Ts13_StringObjectV, ptr %._storage._guts._object, i32 0, i32 1
  store ptr %21, ptr %._storage._guts._object._object, align 8
  %22 = call swiftcc { i64, ptr } @"$sSS21_builtinStringLiteral17utf8CodeUnitCount7isASCIISSBp_BwBi1_tcfC"(ptr @".str.14.SWIFT-BUG-05: ", i64 14, i1 true)
  %23 = extractvalue { i64, ptr } %22, 0
  %24 = extractvalue { i64, ptr } %22, 1
  call swiftcc void @"$ss26DefaultStringInterpolationV13appendLiteralyySSF"(i64 %23, ptr %24, ptr nocapture swiftself dereferenceable(16) %1)
  call void @swift_bridgeObjectRelease(ptr %24) #3
  call void @llvm.lifetime.start.p0(i64 -1, ptr %access-scratch)
  call void @swift_beginAccess(ptr @"$s18red_team_swift_ffi13g_escaped_ptrSPys5UInt8VGSgvp", ptr %access-scratch, i64 32, ptr null) #3
  %25 = load i64, ptr @"$s18red_team_swift_ffi13g_escaped_ptrSPys5UInt8VGSgvp", align 8
  call void @swift_endAccess(ptr %access-scratch) #3
  call void @llvm.lifetime.end.p0(i64 -1, ptr %access-scratch)
  %26 = icmp eq i64 %25, 0
  br i1 %26, label %29, label %27

27:                                               ; preds = %15
  %28 = inttoptr i64 %25 to ptr
  br label %30

29:                                               ; preds = %15
  call swiftcc void @"$ss17_assertionFailure__4file4line5flagss5NeverOs12StaticStringV_A2HSus6UInt32VtF"(i64 ptrtoint (ptr @".str.11.Fatal error" to i64), i64 11, i8 2, i64 ptrtoint (ptr @".str.57.Unexpectedly found nil while unwrapping an Optional value" to i64), i64 57, i8 2, i64 ptrtoint (ptr @".str.43.red_team_swift_ffi/red_team_swift_ffi.swift" to i64), i64 43, i8 2, i64 138, i32 1)
  unreachable

30:                                               ; preds = %27
  %31 = phi ptr [ %28, %27 ]
  %._value5 = getelementptr inbounds %Ts5UInt8V, ptr %31, i32 0, i32 0
  %32 = load i8, ptr %._value5, align 1
  call void @llvm.lifetime.start.p0(i64 1, ptr %2)
  %._value6 = getelementptr inbounds %Ts5UInt8V, ptr %2, i32 0, i32 0
  store i8 %32, ptr %._value6, align 1
  call swiftcc void @"$ss26DefaultStringInterpolationV06appendC0yyxs06CustomB11ConvertibleRzlF"(ptr noalias %2, ptr @"$ss5UInt8VN", ptr @"$ss5UInt8Vs23CustomStringConvertiblesWP", ptr nocapture swiftself dereferenceable(16) %1)
  call void @llvm.lifetime.end.p0(i64 1, ptr %2)
  %33 = call swiftcc { i64, ptr } @"$sSS21_builtinStringLiteral17utf8CodeUnitCount7isASCIISSBp_BwBi1_tcfC"(ptr @.str.0., i64 0, i1 true)
  %34 = extractvalue { i64, ptr } %33, 0
  %35 = extractvalue { i64, ptr } %33, 1
  call swiftcc void @"$ss26DefaultStringInterpolationV13appendLiteralyySSF"(i64 %34, ptr %35, ptr nocapture swiftself dereferenceable(16) %1)
  call void @swift_bridgeObjectRelease(ptr %35) #3
  %._storage7 = getelementptr inbounds %Ts26DefaultStringInterpolationV, ptr %1, i32 0, i32 0
  %._storage7._guts = getelementptr inbounds %TSS, ptr %._storage7, i32 0, i32 0
  %._storage7._guts._object = getelementptr inbounds %Ts11_StringGutsV, ptr %._storage7._guts, i32 0, i32 0
  %._storage7._guts._object._countAndFlagsBits = getelementptr inbounds %Ts13_StringObjectV, ptr %._storage7._guts._object, i32 0, i32 0
  %._storage7._guts._object._countAndFlagsBits._value = getelementptr inbounds %Ts6UInt64V, ptr %._storage7._guts._object._countAndFlagsBits, i32 0, i32 0
  %36 = load i64, ptr %._storage7._guts._object._countAndFlagsBits._value, align 8
  %._storage7._guts._object._object = getelementptr inbounds %Ts13_StringObjectV, ptr %._storage7._guts._object, i32 0, i32 1
  %37 = load ptr, ptr %._storage7._guts._object._object, align 8
  %38 = call ptr @swift_bridgeObjectRetain(ptr returned %37) #3
  %39 = call ptr @"$ss26DefaultStringInterpolationVWOh"(ptr %1)
  call void @llvm.lifetime.end.p0(i64 16, ptr %1)
  %40 = call swiftcc { i64, ptr } @"$sSS19stringInterpolationSSs013DefaultStringB0V_tcfC"(i64 %36, ptr %37)
  %41 = extractvalue { i64, ptr } %40, 0
  %42 = extractvalue { i64, ptr } %40, 1
  %43 = getelementptr inbounds %Any, ptr %18, i32 0, i32 1
  store ptr @"$sSSN", ptr %43, align 8
  %44 = getelementptr inbounds %Any, ptr %18, i32 0, i32 0
  %45 = getelementptr inbounds %Any, ptr %18, i32 0, i32 0
  %._guts = getelementptr inbounds %TSS, ptr %45, i32 0, i32 0
  %._guts._object = getelementptr inbounds %Ts11_StringGutsV, ptr %._guts, i32 0, i32 0
  %._guts._object._countAndFlagsBits = getelementptr inbounds %Ts13_StringObjectV, ptr %._guts._object, i32 0, i32 0
  %._guts._object._countAndFlagsBits._value = getelementptr inbounds %Ts6UInt64V, ptr %._guts._object._countAndFlagsBits, i32 0, i32 0
  store i64 %41, ptr %._guts._object._countAndFlagsBits._value, align 8
  %._guts._object._object = getelementptr inbounds %Ts13_StringObjectV, ptr %._guts._object, i32 0, i32 1
  store ptr %42, ptr %._guts._object._object, align 8
  %46 = call swiftcc ptr @"$ss27_finalizeUninitializedArrayySayxGABnlF"(ptr %17, ptr getelementptr inbounds (%swift.full_existential_type, ptr @"$sypN", i32 0, i32 1))
  %47 = call swiftcc { i64, ptr } @"$ss5print_9separator10terminatoryypd_S2StFfA0_"()
  %48 = extractvalue { i64, ptr } %47, 0
  %49 = extractvalue { i64, ptr } %47, 1
  %50 = call swiftcc { i64, ptr } @"$ss5print_9separator10terminatoryypd_S2StFfA1_"()
  %51 = extractvalue { i64, ptr } %50, 0
  %52 = extractvalue { i64, ptr } %50, 1
  call swiftcc void @"$ss5print_9separator10terminatoryypd_S2StF"(ptr %46, i64 %48, ptr %49, i64 %51, ptr %52)
  call void @swift_bridgeObjectRelease(ptr %52) #3
  call void @swift_bridgeObjectRelease(ptr %49) #3
  call void @swift_bridgeObjectRelease(ptr %46) #3
  %53 = call ptr @"$sSays5UInt8VGWOh"(ptr %0)
  call void @llvm.lifetime.end.p0(i64 8, ptr %0)
  ret void

54:                                               ; preds = %entry
  store ptr null, ptr %swifterror, align 8
  unreachable
}

define internal swiftcc void @"$s18red_team_swift_ffi0C22_bug_05_pointer_escapeyyFySPySays5UInt8VGGXEfU_"(ptr noalias nocapture sret(%swift.opaque) %0, ptr %1, ptr swiftself %2, ptr noalias nocapture swifterror dereferenceable(8) %3, ptr %4) #0 {
entry:
  %ptr.debug = alloca ptr, align 8
  call void @llvm.memset.p0.i64(ptr align 8 %ptr.debug, i8 0, i64 8, i1 false)
  %5 = alloca %TSPys5UInt8VGSg, align 8
  %access-scratch = alloca [24 x i8], align 8
  store ptr %1, ptr %ptr.debug, align 8
  call void @llvm.lifetime.start.p0(i64 8, ptr %5)
  call void asm sideeffect "nop", ""()
  %6 = ptrtoint ptr %1 to i64
  store i64 %6, ptr %5, align 8
  %7 = load i64, ptr %5, align 8
  call void @llvm.lifetime.start.p0(i64 -1, ptr %access-scratch)
  call void @swift_beginAccess(ptr @"$s18red_team_swift_ffi13g_escaped_ptrSPys5UInt8VGSgvp", ptr %access-scratch, i64 33, ptr null) #3
  store i64 %7, ptr @"$s18red_team_swift_ffi13g_escaped_ptrSPys5UInt8VGSgvp", align 8
  call void @swift_endAccess(ptr %access-scratch) #3
  call void @llvm.lifetime.end.p0(i64 -1, ptr %access-scratch)
  call void @llvm.lifetime.end.p0(i64 8, ptr %5)
  ret void
}

define linkonce_odr hidden swiftcc void @"$ss17withUnsafePointer2to_q0_xz_q0_SPyxGq_YKXEtq_YKs5ErrorR_Ri_zRi_0_r1_lF"(ptr noalias sret(%swift.opaque) %0, ptr %1, ptr %2, ptr %3, ptr %T, ptr %E, ptr %Result, ptr %E.Error, ptr swiftself %4, ptr noalias nocapture swifterror dereferenceable(8) %5, ptr %6) #0 {
entry:
  %T1 = alloca ptr, align 8
  %E2 = alloca ptr, align 8
  %Result3 = alloca ptr, align 8
  store ptr %T, ptr %T1, align 8
  store ptr %E, ptr %E2, align 8
  store ptr %Result, ptr %Result3, align 8
  %7 = getelementptr inbounds ptr, ptr %E, i64 -1
  %E.valueWitnesses = load ptr, ptr %7, align 8, !invariant.load !39, !dereferenceable !40
  %8 = getelementptr inbounds %swift.vwtable, ptr %E.valueWitnesses, i32 0, i32 8
  %size = load i64, ptr %8, align 8, !invariant.load !39
  %9 = alloca i8, i64 %size, align 16
  call void @llvm.lifetime.start.p0(i64 -1, ptr %9)
  call swiftcc void %2(ptr noalias sret(%swift.opaque) %0, ptr %1, ptr swiftself %3, ptr noalias nocapture swifterror dereferenceable(8) %5, ptr %9)
  %10 = load ptr, ptr %5, align 8
  %11 = icmp ne ptr %10, null
  %12 = ptrtoint ptr %10 to i64
  br i1 %11, label %13, label %16

13:                                               ; preds = %entry
  store ptr null, ptr %5, align 8
  %14 = getelementptr inbounds ptr, ptr %E.valueWitnesses, i32 4
  %InitializeWithTake = load ptr, ptr %14, align 8, !invariant.load !39
  %15 = call ptr %InitializeWithTake(ptr noalias %6, ptr noalias %9, ptr %E) #3
  call void @llvm.lifetime.end.p0(i64 -1, ptr %9)
  store ptr inttoptr (i64 1 to ptr), ptr %5, align 8
  ret void

16:                                               ; preds = %entry
  call void @llvm.lifetime.end.p0(i64 -1, ptr %9)
  ret void
}

define hidden swiftcc void @"$s18red_team_swift_ffi0C21_bug_06_objc_callbackyyF"() #0 {
entry:
  %obj.debug = alloca ptr, align 8
  call void @llvm.memset.p0.i64(ptr align 8 %obj.debug, i8 0, i64 8, i1 false)
  %ctx.debug = alloca ptr, align 8
  call void @llvm.memset.p0.i64(ptr align 8 %ctx.debug, i8 0, i64 8, i1 false)
  %0 = call swiftcc %swift.metadata_response @"$s18red_team_swift_ffi11SwiftObjectCMa"(i64 0) #14
  %1 = extractvalue %swift.metadata_response %0, 0
  %2 = call swiftcc ptr @"$s18red_team_swift_ffi11SwiftObjectCACycfC"(ptr swiftself %1)
  store ptr %2, ptr %obj.debug, align 8
  call void asm sideeffect "nop", ""()
  store ptr %2, ptr %ctx.debug, align 8
  %3 = ptrtoint ptr %2 to i64
  %4 = inttoptr i64 %3 to ptr
  call void @c_ffi_register_callback(ptr @"$s18red_team_swift_ffi0C21_bug_06_objc_callbackyyFySvSg_s5Int32VtcfU_To", ptr %4)
  call void @swift_release(ptr %2) #3
  ret void
}

define internal swiftcc void @"$s18red_team_swift_ffi0C21_bug_06_objc_callbackyyFySvSg_s5Int32VtcfU_"(i64 %0, i32 %1) #0 {
entry:
  %context.debug = alloca i64, align 8
  call void @llvm.memset.p0.i64(ptr align 8 %context.debug, i8 0, i64 8, i1 false)
  %value.debug = alloca i32, align 8
  call void @llvm.memset.p0.i64(ptr align 8 %value.debug, i8 0, i64 4, i1 false)
  %recovered.debug = alloca ptr, align 8
  call void @llvm.memset.p0.i64(ptr align 8 %recovered.debug, i8 0, i64 8, i1 false)
  %2 = alloca %Ts26DefaultStringInterpolationV, align 8
  %3 = alloca %TSi, align 8
  store i64 %0, ptr %context.debug, align 8
  store i32 %1, ptr %value.debug, align 8
  %4 = icmp eq i64 %0, 0
  br i1 %4, label %7, label %5

5:                                                ; preds = %entry
  %6 = inttoptr i64 %0 to ptr
  br label %8

7:                                                ; preds = %entry
  call swiftcc void @"$ss17_assertionFailure__4file4line5flagss5NeverOs12StaticStringV_A2HSus6UInt32VtF"(i64 ptrtoint (ptr @".str.11.Fatal error" to i64), i64 11, i8 2, i64 ptrtoint (ptr @".str.57.Unexpectedly found nil while unwrapping an Optional value" to i64), i64 57, i8 2, i64 ptrtoint (ptr @".str.43.red_team_swift_ffi/red_team_swift_ffi.swift" to i64), i64 43, i8 2, i64 160, i32 1)
  unreachable

8:                                                ; preds = %5
  %9 = phi ptr [ %6, %5 ]
  call void asm sideeffect "nop", ""()
  %10 = call ptr @swift_retain(ptr returned %9) #6
  store ptr %9, ptr %recovered.debug, align 8
  %11 = call swiftcc { ptr, ptr } @"$ss27_allocateUninitializedArrayySayxG_BptBwlF"(i64 1, ptr getelementptr inbounds (%swift.full_existential_type, ptr @"$sypN", i32 0, i32 1))
  %12 = extractvalue { ptr, ptr } %11, 0
  %13 = extractvalue { ptr, ptr } %11, 1
  call void @llvm.lifetime.start.p0(i64 16, ptr %2)
  %14 = call swiftcc { i64, ptr } @"$ss26DefaultStringInterpolationV15literalCapacity18interpolationCountABSi_SitcfC"(i64 10, i64 1)
  %15 = extractvalue { i64, ptr } %14, 0
  %16 = extractvalue { i64, ptr } %14, 1
  %._storage = getelementptr inbounds %Ts26DefaultStringInterpolationV, ptr %2, i32 0, i32 0
  %._storage._guts = getelementptr inbounds %TSS, ptr %._storage, i32 0, i32 0
  %._storage._guts._object = getelementptr inbounds %Ts11_StringGutsV, ptr %._storage._guts, i32 0, i32 0
  %._storage._guts._object._countAndFlagsBits = getelementptr inbounds %Ts13_StringObjectV, ptr %._storage._guts._object, i32 0, i32 0
  %._storage._guts._object._countAndFlagsBits._value = getelementptr inbounds %Ts6UInt64V, ptr %._storage._guts._object._countAndFlagsBits, i32 0, i32 0
  store i64 %15, ptr %._storage._guts._object._countAndFlagsBits._value, align 8
  %._storage._guts._object._object = getelementptr inbounds %Ts13_StringObjectV, ptr %._storage._guts._object, i32 0, i32 1
  store ptr %16, ptr %._storage._guts._object._object, align 8
  %17 = call swiftcc { i64, ptr } @"$sSS21_builtinStringLiteral17utf8CodeUnitCount7isASCIISSBp_BwBi1_tcfC"(ptr @".str.10.callback: ", i64 10, i1 true)
  %18 = extractvalue { i64, ptr } %17, 0
  %19 = extractvalue { i64, ptr } %17, 1
  call swiftcc void @"$ss26DefaultStringInterpolationV13appendLiteralyySSF"(i64 %18, ptr %19, ptr nocapture swiftself dereferenceable(16) %2)
  call void @swift_bridgeObjectRelease(ptr %19) #3
  %20 = load ptr, ptr %9, align 8
  %21 = getelementptr inbounds ptr, ptr %20, i64 11
  %22 = load ptr, ptr %21, align 8, !invariant.load !39
  %23 = call swiftcc i64 %22(ptr swiftself %9)
  call void @llvm.lifetime.start.p0(i64 8, ptr %3)
  %._value = getelementptr inbounds %TSi, ptr %3, i32 0, i32 0
  store i64 %23, ptr %._value, align 8
  call swiftcc void @"$ss26DefaultStringInterpolationV06appendC0yyxs06CustomB11ConvertibleRzlF"(ptr noalias %3, ptr @"$sSiN", ptr @"$sSis23CustomStringConvertiblesWP", ptr nocapture swiftself dereferenceable(16) %2)
  call void @llvm.lifetime.end.p0(i64 8, ptr %3)
  %24 = call swiftcc { i64, ptr } @"$sSS21_builtinStringLiteral17utf8CodeUnitCount7isASCIISSBp_BwBi1_tcfC"(ptr @.str.0., i64 0, i1 true)
  %25 = extractvalue { i64, ptr } %24, 0
  %26 = extractvalue { i64, ptr } %24, 1
  call swiftcc void @"$ss26DefaultStringInterpolationV13appendLiteralyySSF"(i64 %25, ptr %26, ptr nocapture swiftself dereferenceable(16) %2)
  call void @swift_bridgeObjectRelease(ptr %26) #3
  %._storage1 = getelementptr inbounds %Ts26DefaultStringInterpolationV, ptr %2, i32 0, i32 0
  %._storage1._guts = getelementptr inbounds %TSS, ptr %._storage1, i32 0, i32 0
  %._storage1._guts._object = getelementptr inbounds %Ts11_StringGutsV, ptr %._storage1._guts, i32 0, i32 0
  %._storage1._guts._object._countAndFlagsBits = getelementptr inbounds %Ts13_StringObjectV, ptr %._storage1._guts._object, i32 0, i32 0
  %._storage1._guts._object._countAndFlagsBits._value = getelementptr inbounds %Ts6UInt64V, ptr %._storage1._guts._object._countAndFlagsBits, i32 0, i32 0
  %27 = load i64, ptr %._storage1._guts._object._countAndFlagsBits._value, align 8
  %._storage1._guts._object._object = getelementptr inbounds %Ts13_StringObjectV, ptr %._storage1._guts._object, i32 0, i32 1
  %28 = load ptr, ptr %._storage1._guts._object._object, align 8
  %29 = call ptr @swift_bridgeObjectRetain(ptr returned %28) #3
  %30 = call ptr @"$ss26DefaultStringInterpolationVWOh"(ptr %2)
  call void @llvm.lifetime.end.p0(i64 16, ptr %2)
  %31 = call swiftcc { i64, ptr } @"$sSS19stringInterpolationSSs013DefaultStringB0V_tcfC"(i64 %27, ptr %28)
  %32 = extractvalue { i64, ptr } %31, 0
  %33 = extractvalue { i64, ptr } %31, 1
  %34 = getelementptr inbounds %Any, ptr %13, i32 0, i32 1
  store ptr @"$sSSN", ptr %34, align 8
  %35 = getelementptr inbounds %Any, ptr %13, i32 0, i32 0
  %36 = getelementptr inbounds %Any, ptr %13, i32 0, i32 0
  %._guts = getelementptr inbounds %TSS, ptr %36, i32 0, i32 0
  %._guts._object = getelementptr inbounds %Ts11_StringGutsV, ptr %._guts, i32 0, i32 0
  %._guts._object._countAndFlagsBits = getelementptr inbounds %Ts13_StringObjectV, ptr %._guts._object, i32 0, i32 0
  %._guts._object._countAndFlagsBits._value = getelementptr inbounds %Ts6UInt64V, ptr %._guts._object._countAndFlagsBits, i32 0, i32 0
  store i64 %32, ptr %._guts._object._countAndFlagsBits._value, align 8
  %._guts._object._object = getelementptr inbounds %Ts13_StringObjectV, ptr %._guts._object, i32 0, i32 1
  store ptr %33, ptr %._guts._object._object, align 8
  %37 = call swiftcc ptr @"$ss27_finalizeUninitializedArrayySayxGABnlF"(ptr %12, ptr getelementptr inbounds (%swift.full_existential_type, ptr @"$sypN", i32 0, i32 1))
  %38 = call swiftcc { i64, ptr } @"$ss5print_9separator10terminatoryypd_S2StFfA0_"()
  %39 = extractvalue { i64, ptr } %38, 0
  %40 = extractvalue { i64, ptr } %38, 1
  %41 = call swiftcc { i64, ptr } @"$ss5print_9separator10terminatoryypd_S2StFfA1_"()
  %42 = extractvalue { i64, ptr } %41, 0
  %43 = extractvalue { i64, ptr } %41, 1
  call swiftcc void @"$ss5print_9separator10terminatoryypd_S2StF"(ptr %37, i64 %39, ptr %40, i64 %42, ptr %43)
  call void @swift_bridgeObjectRelease(ptr %43) #3
  call void @swift_bridgeObjectRelease(ptr %40) #3
  call void @swift_bridgeObjectRelease(ptr %37) #3
  call void @swift_release(ptr %9) #3
  ret void
}

define internal void @"$s18red_team_swift_ffi0C21_bug_06_objc_callbackyyFySvSg_s5Int32VtcfU_To"(ptr %0, i32 %1) #0 {
entry:
  %2 = ptrtoint ptr %0 to i64
  call swiftcc void @"$s18red_team_swift_ffi0C21_bug_06_objc_callbackyyFySvSg_s5Int32VtcfU_"(i64 %2, i32 %1) #15
  ret void
}

define hidden swiftcc void @"$s18red_team_swift_ffi0C20_bug_07_array_escapeyyF"() #0 {
entry:
  %arr.debug = alloca ptr, align 8
  call void @llvm.memset.p0.i64(ptr align 8 %arr.debug, i8 0, i64 8, i1 false)
  %swifterror = alloca swifterror ptr, align 8
  store ptr null, ptr %swifterror, align 8
  %0 = alloca %Ts26DefaultStringInterpolationV, align 8
  %access-scratch = alloca [24 x i8], align 8
  %1 = alloca %Ts5UInt8V, align 1
  %2 = call swiftcc { ptr, ptr } @"$ss27_allocateUninitializedArrayySayxG_BptBwlF"(i64 5, ptr @"$ss5UInt8VN")
  %3 = extractvalue { ptr, ptr } %2, 0
  %4 = extractvalue { ptr, ptr } %2, 1
  %._value = getelementptr inbounds %Ts5UInt8V, ptr %4, i32 0, i32 0
  store i8 10, ptr %._value, align 1
  %5 = getelementptr inbounds %Ts5UInt8V, ptr %4, i64 1
  %._value1 = getelementptr inbounds %Ts5UInt8V, ptr %5, i32 0, i32 0
  store i8 20, ptr %._value1, align 1
  %6 = getelementptr inbounds %Ts5UInt8V, ptr %4, i64 2
  %._value2 = getelementptr inbounds %Ts5UInt8V, ptr %6, i32 0, i32 0
  store i8 30, ptr %._value2, align 1
  %7 = getelementptr inbounds %Ts5UInt8V, ptr %4, i64 3
  %._value3 = getelementptr inbounds %Ts5UInt8V, ptr %7, i32 0, i32 0
  store i8 40, ptr %._value3, align 1
  %8 = getelementptr inbounds %Ts5UInt8V, ptr %4, i64 4
  %._value4 = getelementptr inbounds %Ts5UInt8V, ptr %8, i32 0, i32 0
  store i8 50, ptr %._value4, align 1
  %9 = call swiftcc ptr @"$ss27_finalizeUninitializedArrayySayxGABnlF"(ptr %3, ptr @"$ss5UInt8VN")
  store ptr %9, ptr %arr.debug, align 8
  call swiftcc void @"$sSa23withUnsafeBufferPointeryqd__qd__SRyxGqd_0_YKXEqd_0_YKs5ErrorRd_0_r0_lF"(ptr noalias sret(%swift.opaque) undef, ptr @"$s18red_team_swift_ffi0C20_bug_07_array_escapeyyFySRys5UInt8VGXEfU_", ptr null, ptr %9, ptr @"$ss5UInt8VN", ptr getelementptr inbounds (%swift.full_existential_type, ptr @"$sytN", i32 0, i32 1), ptr @"$ss5NeverON", ptr @"$ss5NeverOs5ErrorsWP", ptr swiftself undef, ptr noalias nocapture swifterror dereferenceable(8) %swifterror, ptr undef)
  %10 = load ptr, ptr %swifterror, align 8
  %11 = icmp ne ptr %10, null
  %12 = ptrtoint ptr %10 to i64
  br i1 %11, label %64, label %13

13:                                               ; preds = %entry
  %14 = call swiftcc { ptr, ptr } @"$ss27_allocateUninitializedArrayySayxG_BptBwlF"(i64 1, ptr getelementptr inbounds (%swift.full_existential_type, ptr @"$sypN", i32 0, i32 1))
  %15 = extractvalue { ptr, ptr } %14, 0
  %16 = extractvalue { ptr, ptr } %14, 1
  call void @llvm.lifetime.start.p0(i64 16, ptr %0)
  %17 = call swiftcc { i64, ptr } @"$ss26DefaultStringInterpolationV15literalCapacity18interpolationCountABSi_SitcfC"(i64 14, i64 1)
  %18 = extractvalue { i64, ptr } %17, 0
  %19 = extractvalue { i64, ptr } %17, 1
  %._storage = getelementptr inbounds %Ts26DefaultStringInterpolationV, ptr %0, i32 0, i32 0
  %._storage._guts = getelementptr inbounds %TSS, ptr %._storage, i32 0, i32 0
  %._storage._guts._object = getelementptr inbounds %Ts11_StringGutsV, ptr %._storage._guts, i32 0, i32 0
  %._storage._guts._object._countAndFlagsBits = getelementptr inbounds %Ts13_StringObjectV, ptr %._storage._guts._object, i32 0, i32 0
  %._storage._guts._object._countAndFlagsBits._value = getelementptr inbounds %Ts6UInt64V, ptr %._storage._guts._object._countAndFlagsBits, i32 0, i32 0
  store i64 %18, ptr %._storage._guts._object._countAndFlagsBits._value, align 8
  %._storage._guts._object._object = getelementptr inbounds %Ts13_StringObjectV, ptr %._storage._guts._object, i32 0, i32 1
  store ptr %19, ptr %._storage._guts._object._object, align 8
  %20 = call swiftcc { i64, ptr } @"$sSS21_builtinStringLiteral17utf8CodeUnitCount7isASCIISSBp_BwBi1_tcfC"(ptr @".str.14.SWIFT-BUG-07: ", i64 14, i1 true)
  %21 = extractvalue { i64, ptr } %20, 0
  %22 = extractvalue { i64, ptr } %20, 1
  call swiftcc void @"$ss26DefaultStringInterpolationV13appendLiteralyySSF"(i64 %21, ptr %22, ptr nocapture swiftself dereferenceable(16) %0)
  call void @swift_bridgeObjectRelease(ptr %22) #3
  call void @llvm.lifetime.start.p0(i64 -1, ptr %access-scratch)
  call void @swift_beginAccess(ptr @"$s18red_team_swift_ffi14g_array_bufferSRys5UInt8VGSgvp", ptr %access-scratch, i64 32, ptr null) #3
  %23 = load i64, ptr @"$s18red_team_swift_ffi14g_array_bufferSRys5UInt8VGSgvp", align 8
  %24 = load i64, ptr getelementptr inbounds ({ i64, i64 }, ptr @"$s18red_team_swift_ffi14g_array_bufferSRys5UInt8VGSgvp", i32 0, i32 1), align 8
  %25 = load i1, ptr getelementptr inbounds (%TSRys5UInt8VGSg, ptr @"$s18red_team_swift_ffi14g_array_bufferSRys5UInt8VGSgvp", i32 0, i32 1), align 8
  call void @swift_endAccess(ptr %access-scratch) #3
  call void @llvm.lifetime.end.p0(i64 -1, ptr %access-scratch)
  br i1 %25, label %27, label %26

26:                                               ; preds = %13
  br label %28

27:                                               ; preds = %13
  call swiftcc void @"$ss17_assertionFailure__4file4line5flagss5NeverOs12StaticStringV_A2HSus6UInt32VtF"(i64 ptrtoint (ptr @".str.11.Fatal error" to i64), i64 11, i8 2, i64 ptrtoint (ptr @".str.57.Unexpectedly found nil while unwrapping an Optional value" to i64), i64 57, i8 2, i64 ptrtoint (ptr @".str.43.red_team_swift_ffi/red_team_swift_ffi.swift" to i64), i64 43, i8 2, i64 186, i32 1)
  unreachable

28:                                               ; preds = %26
  %29 = phi i64 [ %23, %26 ]
  %30 = phi i64 [ %24, %26 ]
  %31 = call swiftcc i64 @"$sSR8endIndexSivg"(i64 %29, i64 %30, ptr @"$ss5UInt8VN")
  %32 = icmp slt i64 0, %31
  %33 = call i1 @llvm.expect.i1(i1 %32, i1 true)
  br i1 %33, label %35, label %34

34:                                               ; preds = %28
  call swiftcc void @"$ss18_fatalErrorMessage__4file4line5flagss5NeverOs12StaticStringV_A2HSus6UInt32VtF"(i64 ptrtoint (ptr @".str.11.Fatal error" to i64), i64 11, i8 2, i64 ptrtoint (ptr @.str.0. to i64), i64 0, i8 2, i64 ptrtoint (ptr @".str.39.Swift/arm64e-apple-macos.swiftinterface" to i64), i64 39, i8 2, i64 45701, i32 1)
  unreachable

35:                                               ; preds = %28
  %36 = icmp eq i64 %29, 0
  br i1 %36, label %63, label %37

37:                                               ; preds = %35
  %38 = inttoptr i64 %29 to ptr
  br label %39

39:                                               ; preds = %37
  %40 = phi ptr [ %38, %37 ]
  %41 = inttoptr i64 %29 to ptr
  %._value5 = getelementptr inbounds %Ts5UInt8V, ptr %41, i32 0, i32 0
  %42 = load i8, ptr %._value5, align 1
  call void @llvm.lifetime.start.p0(i64 1, ptr %1)
  %._value6 = getelementptr inbounds %Ts5UInt8V, ptr %1, i32 0, i32 0
  store i8 %42, ptr %._value6, align 1
  call swiftcc void @"$ss26DefaultStringInterpolationV06appendC0yyxs06CustomB11ConvertibleRzlF"(ptr noalias %1, ptr @"$ss5UInt8VN", ptr @"$ss5UInt8Vs23CustomStringConvertiblesWP", ptr nocapture swiftself dereferenceable(16) %0)
  call void @llvm.lifetime.end.p0(i64 1, ptr %1)
  %43 = call swiftcc { i64, ptr } @"$sSS21_builtinStringLiteral17utf8CodeUnitCount7isASCIISSBp_BwBi1_tcfC"(ptr @.str.0., i64 0, i1 true)
  %44 = extractvalue { i64, ptr } %43, 0
  %45 = extractvalue { i64, ptr } %43, 1
  call swiftcc void @"$ss26DefaultStringInterpolationV13appendLiteralyySSF"(i64 %44, ptr %45, ptr nocapture swiftself dereferenceable(16) %0)
  call void @swift_bridgeObjectRelease(ptr %45) #3
  %._storage7 = getelementptr inbounds %Ts26DefaultStringInterpolationV, ptr %0, i32 0, i32 0
  %._storage7._guts = getelementptr inbounds %TSS, ptr %._storage7, i32 0, i32 0
  %._storage7._guts._object = getelementptr inbounds %Ts11_StringGutsV, ptr %._storage7._guts, i32 0, i32 0
  %._storage7._guts._object._countAndFlagsBits = getelementptr inbounds %Ts13_StringObjectV, ptr %._storage7._guts._object, i32 0, i32 0
  %._storage7._guts._object._countAndFlagsBits._value = getelementptr inbounds %Ts6UInt64V, ptr %._storage7._guts._object._countAndFlagsBits, i32 0, i32 0
  %46 = load i64, ptr %._storage7._guts._object._countAndFlagsBits._value, align 8
  %._storage7._guts._object._object = getelementptr inbounds %Ts13_StringObjectV, ptr %._storage7._guts._object, i32 0, i32 1
  %47 = load ptr, ptr %._storage7._guts._object._object, align 8
  %48 = call ptr @swift_bridgeObjectRetain(ptr returned %47) #3
  %49 = call ptr @"$ss26DefaultStringInterpolationVWOh"(ptr %0)
  call void @llvm.lifetime.end.p0(i64 16, ptr %0)
  %50 = call swiftcc { i64, ptr } @"$sSS19stringInterpolationSSs013DefaultStringB0V_tcfC"(i64 %46, ptr %47)
  %51 = extractvalue { i64, ptr } %50, 0
  %52 = extractvalue { i64, ptr } %50, 1
  %53 = getelementptr inbounds %Any, ptr %16, i32 0, i32 1
  store ptr @"$sSSN", ptr %53, align 8
  %54 = getelementptr inbounds %Any, ptr %16, i32 0, i32 0
  %55 = getelementptr inbounds %Any, ptr %16, i32 0, i32 0
  %._guts = getelementptr inbounds %TSS, ptr %55, i32 0, i32 0
  %._guts._object = getelementptr inbounds %Ts11_StringGutsV, ptr %._guts, i32 0, i32 0
  %._guts._object._countAndFlagsBits = getelementptr inbounds %Ts13_StringObjectV, ptr %._guts._object, i32 0, i32 0
  %._guts._object._countAndFlagsBits._value = getelementptr inbounds %Ts6UInt64V, ptr %._guts._object._countAndFlagsBits, i32 0, i32 0
  store i64 %51, ptr %._guts._object._countAndFlagsBits._value, align 8
  %._guts._object._object = getelementptr inbounds %Ts13_StringObjectV, ptr %._guts._object, i32 0, i32 1
  store ptr %52, ptr %._guts._object._object, align 8
  %56 = call swiftcc ptr @"$ss27_finalizeUninitializedArrayySayxGABnlF"(ptr %15, ptr getelementptr inbounds (%swift.full_existential_type, ptr @"$sypN", i32 0, i32 1))
  %57 = call swiftcc { i64, ptr } @"$ss5print_9separator10terminatoryypd_S2StFfA0_"()
  %58 = extractvalue { i64, ptr } %57, 0
  %59 = extractvalue { i64, ptr } %57, 1
  %60 = call swiftcc { i64, ptr } @"$ss5print_9separator10terminatoryypd_S2StFfA1_"()
  %61 = extractvalue { i64, ptr } %60, 0
  %62 = extractvalue { i64, ptr } %60, 1
  call swiftcc void @"$ss5print_9separator10terminatoryypd_S2StF"(ptr %56, i64 %58, ptr %59, i64 %61, ptr %62)
  call void @swift_bridgeObjectRelease(ptr %62) #3
  call void @swift_bridgeObjectRelease(ptr %59) #3
  call void @swift_bridgeObjectRelease(ptr %56) #3
  call void @swift_bridgeObjectRelease(ptr %9) #3
  ret void

63:                                               ; preds = %35
  unreachable

64:                                               ; preds = %entry
  store ptr null, ptr %swifterror, align 8
  unreachable
}

; Function Attrs: nocallback nofree nosync nounwind willreturn memory(argmem: readwrite)
declare void @llvm.lifetime.start.p0(i64 immarg, ptr nocapture) #2

; Function Attrs: nounwind
declare void @swift_beginAccess(ptr, ptr, i64, ptr) #3

; Function Attrs: nounwind
declare void @swift_endAccess(ptr) #3

; Function Attrs: nocallback nofree nosync nounwind willreturn memory(argmem: readwrite)
declare void @llvm.lifetime.end.p0(i64 immarg, ptr nocapture) #2

; Function Attrs: nocallback nofree nounwind willreturn memory(argmem: write)
declare void @llvm.memset.p0.i64(ptr nocapture writeonly, i8, i64, i1 immarg) #4

declare swiftcc { ptr, ptr } @"$ss27_allocateUninitializedArrayySayxG_BptBwlF"(i64, ptr) #0

declare swiftcc { i64, ptr } @"$sSS21_builtinStringLiteral17utf8CodeUnitCount7isASCIISSBp_BwBi1_tcfC"(ptr, i64, i1) #0

declare swiftcc void @"$ss5print_9separator10terminatoryypd_S2StF"(ptr, i64, ptr, i64, ptr) #0

; Function Attrs: nounwind
declare void @swift_bridgeObjectRelease(ptr) #3

; Function Attrs: nounwind
declare void @swift_deallocClassInstance(ptr, i64, i64) #3

; Function Attrs: nounwind
declare ptr @swift_allocObject(ptr, i64, i64) #3

; Function Attrs: noinline nounwind memory(none)
define hidden swiftcc %swift.metadata_response @"$s18red_team_swift_ffi11SwiftObjectCMa"(i64 %0) #5 {
entry:
  %1 = call ptr @objc_opt_self(ptr getelementptr inbounds (<{ ptr, ptr, ptr, i64, ptr, ptr, ptr, ptr, i32, i32, i32, i16, i16, i32, i32, ptr, ptr, i64, ptr, ptr, ptr, ptr }>, ptr @"$s18red_team_swift_ffi11SwiftObjectCMf", i32 0, i32 3)) #3
  %2 = insertvalue %swift.metadata_response undef, ptr %1, 0
  %3 = insertvalue %swift.metadata_response %2, i64 0, 1
  ret %swift.metadata_response %3
}

; Function Attrs: nounwind willreturn
declare ptr @swift_retain(ptr returned) #6

; Function Attrs: nounwind willreturn
declare ptr @swift_unownedRetain(ptr returned) #6

; Function Attrs: nounwind
declare void @swift_release(ptr) #3

declare swiftcc { i64, ptr } @"$ss26DefaultStringInterpolationV15literalCapacity18interpolationCountABSi_SitcfC"(i64, i64) #0

declare swiftcc void @"$ss26DefaultStringInterpolationV13appendLiteralyySSF"(i64, ptr, ptr nocapture swiftself dereferenceable(16)) #0

; Function Attrs: nounwind willreturn
declare ptr @swift_unownedRetainStrong(ptr returned) #6

declare swiftcc void @"$ss26DefaultStringInterpolationV06appendC0yyxs06CustomB11ConvertibleRzlF"(ptr noalias, ptr, ptr, ptr nocapture swiftself dereferenceable(16)) #0

; Function Attrs: nounwind
declare ptr @swift_bridgeObjectRetain(ptr returned) #3

; Function Attrs: noinline nounwind
define linkonce_odr hidden ptr @"$ss26DefaultStringInterpolationVWOh"(ptr %0) #7 {
entry:
  %._storage = getelementptr inbounds %Ts26DefaultStringInterpolationV, ptr %0, i32 0, i32 0
  %._storage._guts = getelementptr inbounds %TSS, ptr %._storage, i32 0, i32 0
  %._storage._guts._object = getelementptr inbounds %Ts11_StringGutsV, ptr %._storage._guts, i32 0, i32 0
  %._storage._guts._object._object = getelementptr inbounds %Ts13_StringObjectV, ptr %._storage._guts._object, i32 0, i32 1
  %toDestroy = load ptr, ptr %._storage._guts._object._object, align 8
  call void @swift_bridgeObjectRelease(ptr %toDestroy) #3
  ret ptr %0
}

declare swiftcc { i64, ptr } @"$sSS19stringInterpolationSSs013DefaultStringB0V_tcfC"(i64, ptr) #0

; Function Attrs: nounwind
declare void @swift_unownedRelease(ptr) #3

; Function Attrs: noinline nounwind
define linkonce_odr hidden ptr @"$s18red_team_swift_ffi11SwiftObjectCSgWOh"(ptr %0) #7 {
entry:
  %1 = load ptr, ptr %0, align 8
  call void @swift_release(ptr %1) #3
  ret ptr %0
}

; Function Attrs: nounwind willreturn
declare ptr @swift_weakInit(ptr returned, ptr) #6

; Function Attrs: nounwind willreturn
declare ptr @swift_weakLoadStrong(ptr) #6

; Function Attrs: nounwind
declare void @swift_weakDestroy(ptr) #3

declare ptr @c_ffi_alloc(i32 noundef) #0

; Function Attrs: noinline
declare swiftcc void @"$ss17_assertionFailure__4file4line5flagss5NeverOs12StaticStringV_A2HSus6UInt32VtF"(i64, i64, i8, i64, i64, i8, i64, i64, i8, i64, i32) #1

declare void @c_ffi_free(ptr noundef) #0

declare swiftcc void @"$sSv4load14fromByteOffset2asxSi_xmtlF"(ptr noalias sret(%swift.opaque), i64, ptr, ptr, ptr) #0

; Function Attrs: noinline nounwind memory(none)
define linkonce_odr hidden swiftcc %swift.metadata_response @"$sSo8NSStringCMa"(i64 %0) #5 {
entry:
  %1 = load ptr, ptr @"$sSo8NSStringCML", align 8
  %2 = icmp eq ptr %1, null
  br i1 %2, label %cacheIsNull, label %cont

cacheIsNull:                                      ; preds = %entry
  %3 = load ptr, ptr @"OBJC_CLASS_REF_$_NSString", align 8
  %4 = call ptr @objc_opt_self(ptr %3) #3
  %5 = call ptr @swift_getObjCClassMetadata(ptr %4) #8
  store atomic ptr %5, ptr @"$sSo8NSStringCML" release, align 8
  br label %cont

cont:                                             ; preds = %cacheIsNull, %entry
  %6 = phi ptr [ %1, %entry ], [ %5, %cacheIsNull ]
  %7 = insertvalue %swift.metadata_response undef, ptr %6, 0
  %8 = insertvalue %swift.metadata_response %7, i64 0, 1
  ret %swift.metadata_response %8
}

; Function Attrs: nounwind
declare ptr @objc_opt_self(ptr) #3

; Function Attrs: nounwind willreturn memory(none)
declare ptr @swift_getObjCClassMetadata(ptr) #8

declare swiftcc ptr @"$sSo8NSStringC10FoundationE13stringLiteralABs12StaticStringV_tcfC"(i64, i64, i8, ptr swiftself) #0

; Function Attrs: nounwind
declare ptr @llvm.objc.retain(ptr) #3

declare swiftcc { i64, ptr } @"$sSS10FoundationE36_unconditionallyBridgeFromObjectiveCySSSo8NSStringCSgFZ"(i64) #0

; Function Attrs: nounwind
declare void @llvm.objc.release(ptr) #3

; Function Attrs: nounwind
declare void @swift_unknownObjectRelease(ptr) #3

declare swiftcc void @"$ss26DefaultStringInterpolationV06appendC0yyxs06CustomB11ConvertibleRzs20TextOutputStreamableRzlF"(ptr noalias, ptr, ptr, ptr, ptr nocapture swiftself dereferenceable(16)) #0

; Function Attrs: noinline nounwind willreturn memory(read)
define linkonce_odr hidden ptr @__swift_instantiateConcreteTypeFromMangledNameV2(ptr %0, ptr %1) #9 {
entry:
  %2 = load atomic ptr, ptr %0 monotonic, align 8
  %3 = icmp eq ptr %2, null
  %4 = ptrtoint ptr %2 to i64
  %5 = and i64 %4, 1
  %6 = icmp eq i64 %5, 1
  %7 = or i1 %6, %3
  br i1 %7, label %10, label %8

8:                                                ; preds = %10, %entry
  %9 = phi ptr [ %2, %entry ], [ %18, %10 ]
  ret ptr %9

10:                                               ; preds = %entry
  %11 = load i64, ptr %1, align 8
  %12 = ashr i64 %11, 32
  %13 = trunc i64 %11 to i32
  %14 = sext i32 %13 to i64
  %15 = ptrtoint ptr %1 to i64
  %16 = add i64 %15, %14
  %17 = inttoptr i64 %16 to ptr
  %18 = call swiftcc ptr @swift_getTypeByMangledNameInContext2(ptr %17, i64 %12, ptr null, ptr null) #16
  store atomic ptr %18, ptr %0 monotonic, align 8
  br label %8
}

; Function Attrs: nounwind memory(argmem: readwrite)
declare swiftcc ptr @swift_getTypeByMangledNameInContext2(ptr, i64, ptr, ptr) #10

; Function Attrs: noinline nounwind
define linkonce_odr hidden ptr @"$sSays5UInt8VGWOh"(ptr %0) #7 {
entry:
  %._buffer = getelementptr inbounds %TSa, ptr %0, i32 0, i32 0
  %._buffer._storage = getelementptr inbounds %Ts12_ArrayBufferV, ptr %._buffer, i32 0, i32 0
  %._buffer._storage.rawValue = getelementptr inbounds %Ts14_BridgeStorageV, ptr %._buffer._storage, i32 0, i32 0
  %toDestroy = load ptr, ptr %._buffer._storage.rawValue, align 8
  call void @swift_bridgeObjectRelease(ptr %toDestroy) #3
  ret ptr %0
}

declare void @c_ffi_register_callback(ptr noundef, ptr noundef) #0

define internal swiftcc void @"$s18red_team_swift_ffi0C20_bug_07_array_escapeyyFySRys5UInt8VGXEfU_"(ptr noalias nocapture sret(%swift.opaque) %0, i64 %1, i64 %2, ptr swiftself %3, ptr noalias nocapture swifterror dereferenceable(8) %4, ptr %5) #0 {
entry:
  %buffer.debug = alloca %TSRys5UInt8VG, align 8
  call void @llvm.memset.p0.i64(ptr align 8 %buffer.debug, i8 0, i64 16, i1 false)
  %access-scratch = alloca [24 x i8], align 8
  call void @llvm.lifetime.start.p0(i64 16, ptr %buffer.debug)
  %buffer.debug._position = getelementptr inbounds %TSRys5UInt8VG, ptr %buffer.debug, i32 0, i32 0
  store i64 %1, ptr %buffer.debug._position, align 8
  %buffer.debug.count = getelementptr inbounds %TSRys5UInt8VG, ptr %buffer.debug, i32 0, i32 1
  %buffer.debug.count._value = getelementptr inbounds %TSi, ptr %buffer.debug.count, i32 0, i32 0
  store i64 %2, ptr %buffer.debug.count._value, align 8
  call void @llvm.lifetime.start.p0(i64 -1, ptr %access-scratch)
  call void @swift_beginAccess(ptr @"$s18red_team_swift_ffi14g_array_bufferSRys5UInt8VGSgvp", ptr %access-scratch, i64 33, ptr null) #3
  store i64 %1, ptr @"$s18red_team_swift_ffi14g_array_bufferSRys5UInt8VGSgvp", align 8
  store i64 %2, ptr getelementptr inbounds ({ i64, i64 }, ptr @"$s18red_team_swift_ffi14g_array_bufferSRys5UInt8VGSgvp", i32 0, i32 1), align 8
  store i1 false, ptr getelementptr inbounds (%TSRys5UInt8VGSg, ptr @"$s18red_team_swift_ffi14g_array_bufferSRys5UInt8VGSgvp", i32 0, i32 1), align 8
  call void @swift_endAccess(ptr %access-scratch) #3
  call void @llvm.lifetime.end.p0(i64 -1, ptr %access-scratch)
  ret void
}

define linkonce_odr hidden swiftcc void @"$sSa23withUnsafeBufferPointeryqd__qd__SRyxGqd_0_YKXEqd_0_YKs5ErrorRd_0_r0_lF"(ptr noalias sret(%swift.opaque) %0, ptr %1, ptr %2, ptr %3, ptr %Element, ptr %R, ptr %E, ptr %E.Error, ptr swiftself %4, ptr noalias nocapture swifterror dereferenceable(8) %5, ptr %6) #0 {
entry:
  %Element1 = alloca ptr, align 8
  %R2 = alloca ptr, align 8
  %E3 = alloca ptr, align 8
  store ptr %Element, ptr %Element1, align 8
  store ptr %R, ptr %R2, align 8
  store ptr %E, ptr %E3, align 8
  %7 = getelementptr inbounds ptr, ptr %E, i64 -1
  %E.valueWitnesses = load ptr, ptr %7, align 8, !invariant.load !39, !dereferenceable !40
  %8 = getelementptr inbounds %swift.vwtable, ptr %E.valueWitnesses, i32 0, i32 8
  %size = load i64, ptr %8, align 8, !invariant.load !39
  %9 = alloca i8, i64 %size, align 16
  call void @llvm.lifetime.start.p0(i64 -1, ptr %9)
  call swiftcc void @"$ss12_ArrayBufferV010withUnsafeB7Pointeryqd__qd__SRyxGqd_0_YKXEqd_0_YKs5ErrorRd_0_r0_lF"(ptr noalias sret(%swift.opaque) %0, ptr %1, ptr %2, ptr %3, ptr %Element, ptr %R, ptr %E, ptr %E.Error, ptr swiftself undef, ptr noalias nocapture swifterror dereferenceable(8) %5, ptr %9)
  %10 = load ptr, ptr %5, align 8
  %11 = icmp ne ptr %10, null
  %12 = ptrtoint ptr %10 to i64
  br i1 %11, label %13, label %16

13:                                               ; preds = %entry
  store ptr null, ptr %5, align 8
  %14 = getelementptr inbounds ptr, ptr %E.valueWitnesses, i32 4
  %InitializeWithTake = load ptr, ptr %14, align 8, !invariant.load !39
  %15 = call ptr %InitializeWithTake(ptr noalias %6, ptr noalias %9, ptr %E) #3
  call void @llvm.lifetime.end.p0(i64 -1, ptr %9)
  store ptr inttoptr (i64 1 to ptr), ptr %5, align 8
  ret void

16:                                               ; preds = %entry
  call void @llvm.lifetime.end.p0(i64 -1, ptr %9)
  ret void
}

declare swiftcc i64 @"$sSR8endIndexSivg"(i64, i64, ptr) #0

; Function Attrs: nocallback nofree nosync nounwind willreturn memory(none)
declare i1 @llvm.expect.i1(i1, i1) #11

; Function Attrs: noinline
declare swiftcc void @"$ss18_fatalErrorMessage__4file4line5flagss5NeverOs12StaticStringV_A2HSus6UInt32VtF"(i64, i64, i8, i64, i64, i8, i64, i64, i8, i64, i32) #1

declare extern_weak void @"_swift_FORCE_LOAD_$_swiftFoundation"()

declare extern_weak void @"_swift_FORCE_LOAD_$_swift_Builtin_float"()

declare extern_weak void @"_swift_FORCE_LOAD_$_swiftObjectiveC"()

declare extern_weak void @"_swift_FORCE_LOAD_$_swiftCoreFoundation"()

declare extern_weak void @"_swift_FORCE_LOAD_$_swiftDispatch"()

declare extern_weak void @"_swift_FORCE_LOAD_$_swiftXPC"()

declare extern_weak void @"_swift_FORCE_LOAD_$_swiftIOKit"()

define linkonce_odr hidden swiftcc void @"$sSa12_endMutationyyF"(ptr %"Array<Element>", ptr nocapture swiftself dereferenceable(8) %0) #0 {
entry:
  %._buffer = getelementptr inbounds %TSa, ptr %0, i32 0, i32 0
  %._buffer._storage = getelementptr inbounds %Ts12_ArrayBufferV, ptr %._buffer, i32 0, i32 0
  %._buffer._storage.rawValue = getelementptr inbounds %Ts14_BridgeStorageV, ptr %._buffer._storage, i32 0, i32 0
  %1 = load ptr, ptr %._buffer._storage.rawValue, align 8
  %._buffer1 = getelementptr inbounds %TSa, ptr %0, i32 0, i32 0
  %._buffer1._storage = getelementptr inbounds %Ts12_ArrayBufferV, ptr %._buffer1, i32 0, i32 0
  %._buffer1._storage.rawValue = getelementptr inbounds %Ts14_BridgeStorageV, ptr %._buffer1._storage, i32 0, i32 0
  store ptr %1, ptr %._buffer1._storage.rawValue, align 8
  ret void
}

define linkonce_odr hidden swiftcc void @"$ss12_ArrayBufferV010withUnsafeB7Pointeryqd__qd__SRyxGqd_0_YKXEqd_0_YKs5ErrorRd_0_r0_lF"(ptr noalias sret(%swift.opaque) %0, ptr %1, ptr %2, ptr %3, ptr %Element, ptr %R, ptr %E, ptr %E.Error, ptr swiftself %4, ptr noalias nocapture swifterror dereferenceable(8) %5, ptr %6) #0 {
entry:
  %Element1 = alloca ptr, align 8
  %R2 = alloca ptr, align 8
  %E3 = alloca ptr, align 8
  store ptr %Element, ptr %Element1, align 8
  store ptr %R, ptr %R2, align 8
  store ptr %E, ptr %E3, align 8
  %7 = getelementptr inbounds ptr, ptr %E, i64 -1
  %E.valueWitnesses = load ptr, ptr %7, align 8, !invariant.load !39, !dereferenceable !40
  %8 = getelementptr inbounds %swift.vwtable, ptr %E.valueWitnesses, i32 0, i32 8
  %size = load i64, ptr %8, align 8, !invariant.load !39
  %9 = alloca i8, i64 %size, align 16
  call void @llvm.lifetime.start.p0(i64 -1, ptr %9)
  %10 = alloca i8, i64 %size, align 16
  call void @llvm.lifetime.start.p0(i64 -1, ptr %10)
  %11 = call swiftcc i1 @"$ss12_ArrayBufferV9_isNativeSbvg"(ptr %3, ptr %Element)
  %12 = call i1 @llvm.expect.i1(i1 %11, i1 true)
  br i1 %12, label %21, label %13

13:                                               ; preds = %entry
  call swiftcc void @"$ss12_ArrayBufferV010withUnsafeB17Pointer_nonNativeyqd__qd__SRyxGqd_0_YKXEqd_0_YKs5ErrorRd_0_r0_lF"(ptr noalias sret(%swift.opaque) %0, ptr %1, ptr %2, ptr %3, ptr %Element, ptr %R, ptr %E, ptr %E.Error, ptr swiftself undef, ptr noalias nocapture swifterror dereferenceable(8) %5, ptr %10)
  %14 = load ptr, ptr %5, align 8
  %15 = icmp ne ptr %14, null
  %16 = ptrtoint ptr %14 to i64
  br i1 %15, label %17, label %20

17:                                               ; preds = %13
  store ptr null, ptr %5, align 8
  %18 = getelementptr inbounds ptr, ptr %E.valueWitnesses, i32 4
  %InitializeWithTake = load ptr, ptr %18, align 8, !invariant.load !39
  %19 = call ptr %InitializeWithTake(ptr noalias %6, ptr noalias %10, ptr %E) #3
  br label %43

20:                                               ; preds = %13
  br label %45

21:                                               ; preds = %entry
  %22 = call swiftcc ptr @"$ss12_ArrayBufferV19firstElementAddressSpyxGvg"(ptr %3, ptr %Element)
  %23 = ptrtoint ptr %22 to i64
  %24 = call swiftcc i1 @"$ss12_ArrayBufferV9_isNativeSbvg"(ptr %3, ptr %Element)
  %25 = call i1 @llvm.expect.i1(i1 %24, i1 true)
  br i1 %25, label %29, label %26

26:                                               ; preds = %21
  %27 = call swiftcc ptr @"$ss12_ArrayBufferV10_nonNatives06_CocoaA7WrapperVvg"(ptr %3, ptr %Element)
  %28 = call swiftcc i64 @"$ss18_CocoaArrayWrapperV8endIndexSivg"(ptr %27)
  call void @swift_unknownObjectRelease(ptr %27) #3
  br label %32

29:                                               ; preds = %21
  %30 = call swiftcc ptr @"$ss12_ArrayBufferV7_natives011_ContiguousaB0VyxGvg"(ptr %3, ptr %Element)
  %31 = call swiftcc i64 @"$ss22_ContiguousArrayBufferV5countSivg"(ptr %30, ptr %Element)
  call void @swift_release(ptr %30) #3
  br label %32

32:                                               ; preds = %29, %26
  %33 = phi i64 [ %28, %26 ], [ %31, %29 ]
  %34 = call swiftcc { i64, i64 } @"$sSR5start5countSRyxGSPyxGSg_SitcfC"(i64 %23, i64 %33, ptr %Element)
  %35 = extractvalue { i64, i64 } %34, 0
  %36 = extractvalue { i64, i64 } %34, 1
  call swiftcc void %1(ptr noalias sret(%swift.opaque) %0, i64 %35, i64 %36, ptr swiftself %2, ptr noalias nocapture swifterror dereferenceable(8) %5, ptr %9)
  %37 = load ptr, ptr %5, align 8
  %38 = icmp ne ptr %37, null
  %39 = ptrtoint ptr %37 to i64
  br i1 %38, label %40, label %44

40:                                               ; preds = %32
  store ptr null, ptr %5, align 8
  %41 = getelementptr inbounds ptr, ptr %E.valueWitnesses, i32 4
  %InitializeWithTake4 = load ptr, ptr %41, align 8, !invariant.load !39
  %42 = call ptr %InitializeWithTake4(ptr noalias %6, ptr noalias %9, ptr %E) #3
  call swiftcc void @"$ss12_ArrayBufferV010withUnsafeB7Pointeryqd__qd__SRyxGqd_0_YKXEqd_0_YKs5ErrorRd_0_r0_lF6$deferL_yysAERd_0_r_0_lF"(ptr %3, ptr %Element, ptr %R, ptr %E, ptr %E.Error)
  br label %43

43:                                               ; preds = %40, %17
  call void @llvm.lifetime.end.p0(i64 -1, ptr %10)
  call void @llvm.lifetime.end.p0(i64 -1, ptr %9)
  store ptr inttoptr (i64 1 to ptr), ptr %5, align 8
  ret void

44:                                               ; preds = %32
  call swiftcc void @"$ss12_ArrayBufferV010withUnsafeB7Pointeryqd__qd__SRyxGqd_0_YKXEqd_0_YKs5ErrorRd_0_r0_lF6$deferL_yysAERd_0_r_0_lF"(ptr %3, ptr %Element, ptr %R, ptr %E, ptr %E.Error)
  br label %45

45:                                               ; preds = %44, %20
  call void @llvm.lifetime.end.p0(i64 -1, ptr %10)
  call void @llvm.lifetime.end.p0(i64 -1, ptr %9)
  ret void
}

declare swiftcc i1 @"$ss12_ArrayBufferV9_isNativeSbvg"(ptr, ptr) #0

; Function Attrs: noinline
define linkonce_odr hidden swiftcc void @"$ss12_ArrayBufferV010withUnsafeB17Pointer_nonNativeyqd__qd__SRyxGqd_0_YKXEqd_0_YKs5ErrorRd_0_r0_lF"(ptr noalias sret(%swift.opaque) %0, ptr %1, ptr %2, ptr %3, ptr %Element, ptr %R, ptr %E, ptr %E.Error, ptr swiftself %4, ptr noalias nocapture swifterror dereferenceable(8) %5, ptr %6) #1 {
entry:
  %Element1 = alloca ptr, align 8
  %R2 = alloca ptr, align 8
  %E3 = alloca ptr, align 8
  store ptr %Element, ptr %Element1, align 8
  store ptr %R, ptr %R2, align 8
  store ptr %E, ptr %E3, align 8
  %7 = getelementptr inbounds ptr, ptr %E, i64 -1
  %E.valueWitnesses = load ptr, ptr %7, align 8, !invariant.load !39, !dereferenceable !40
  %8 = getelementptr inbounds %swift.vwtable, ptr %E.valueWitnesses, i32 0, i32 8
  %size = load i64, ptr %8, align 8, !invariant.load !39
  %9 = alloca i8, i64 %size, align 16
  call void @llvm.lifetime.start.p0(i64 -1, ptr %9)
  %10 = call swiftcc ptr @"$ss12_ArrayBufferV029getOrAllocateAssociatedObjectB0s011_ContiguousaB0VyxGyF"(ptr %3, ptr %Element)
  %11 = call swiftcc ptr @"$ss22_ContiguousArrayBufferV19firstElementAddressSpyxGvg"(ptr %10, ptr %Element)
  %12 = call swiftcc i64 @"$ss22_ContiguousArrayBufferV5countSivg"(ptr %10, ptr %Element)
  call void @swift_release(ptr %10) #3
  %13 = ptrtoint ptr %11 to i64
  %14 = call swiftcc { i64, i64 } @"$sSR5start5countSRyxGSPyxGSg_SitcfC"(i64 %13, i64 %12, ptr %Element)
  %15 = extractvalue { i64, i64 } %14, 0
  %16 = extractvalue { i64, i64 } %14, 1
  call swiftcc void %1(ptr noalias sret(%swift.opaque) %0, i64 %15, i64 %16, ptr swiftself %2, ptr noalias nocapture swifterror dereferenceable(8) %5, ptr %9)
  %17 = load ptr, ptr %5, align 8
  %18 = icmp ne ptr %17, null
  %19 = ptrtoint ptr %17 to i64
  br i1 %18, label %20, label %23

20:                                               ; preds = %entry
  store ptr null, ptr %5, align 8
  %21 = getelementptr inbounds ptr, ptr %E.valueWitnesses, i32 4
  %InitializeWithTake = load ptr, ptr %21, align 8, !invariant.load !39
  %22 = call ptr %InitializeWithTake(ptr noalias %6, ptr noalias %9, ptr %E) #3
  call void @llvm.lifetime.end.p0(i64 -1, ptr %9)
  store ptr inttoptr (i64 1 to ptr), ptr %5, align 8
  ret void

23:                                               ; preds = %entry
  call void @llvm.lifetime.end.p0(i64 -1, ptr %9)
  ret void
}

declare swiftcc ptr @"$ss12_ArrayBufferV19firstElementAddressSpyxGvg"(ptr, ptr) #0

declare swiftcc ptr @"$ss12_ArrayBufferV10_nonNatives06_CocoaA7WrapperVvg"(ptr, ptr) #0

declare swiftcc i64 @"$ss18_CocoaArrayWrapperV8endIndexSivg"(ptr) #0

declare swiftcc { i64, i64 } @"$sSR5start5countSRyxGSPyxGSg_SitcfC"(i64, i64, ptr) #0

define linkonce_odr hidden swiftcc void @"$ss12_ArrayBufferV010withUnsafeB7Pointeryqd__qd__SRyxGqd_0_YKXEqd_0_YKs5ErrorRd_0_r0_lF6$deferL_yysAERd_0_r_0_lF"(ptr %0, ptr %Element, ptr %R, ptr %E, ptr %E.Error) #0 {
entry:
  %Element1 = alloca ptr, align 8
  %R2 = alloca ptr, align 8
  %E3 = alloca ptr, align 8
  store ptr %Element, ptr %Element1, align 8
  store ptr %R, ptr %R2, align 8
  store ptr %E, ptr %E3, align 8
  ret void
}

declare swiftcc ptr @"$ss12_ArrayBufferV7_natives011_ContiguousaB0VyxGvg"(ptr, ptr) #0

declare swiftcc i64 @"$ss22_ContiguousArrayBufferV5countSivg"(ptr, ptr) #0

define linkonce_odr hidden swiftcc ptr @"$ss12_ArrayBufferV029getOrAllocateAssociatedObjectB0s011_ContiguousaB0VyxGyF"(ptr %0, ptr %Element) #0 {
entry:
  %Element1 = alloca ptr, align 8
  %1 = alloca %Ts12_ArrayBufferV, align 8
  store ptr %Element, ptr %Element1, align 8
  %2 = call swiftcc i64 @"$ss12_ArrayBufferV013getAssociatedB0s011_ContiguousaB0VyxGSgyF"(ptr %0, ptr %Element)
  %3 = icmp eq i64 %2, 0
  br i1 %3, label %6, label %4

4:                                                ; preds = %entry
  %5 = inttoptr i64 %2 to ptr
  br label %32

6:                                                ; preds = %entry
  %7 = ptrtoint ptr %0 to i64
  %8 = and i64 %7, -9223372036854775808
  %9 = icmp eq i64 %8, 0
  br i1 %9, label %not-tagged-pointer, label %tagged-pointer

tagged-pointer:                                   ; preds = %6
  br label %tagged-cont

not-tagged-pointer:                               ; preds = %6
  %10 = and i64 %7, 1152921504606846968
  %11 = inttoptr i64 %10 to ptr
  br label %tagged-cont

tagged-cont:                                      ; preds = %not-tagged-pointer, %tagged-pointer
  %12 = phi ptr [ %0, %tagged-pointer ], [ %11, %not-tagged-pointer ]
  %13 = call i32 @objc_sync_enter(ptr %12)
  %14 = call swiftcc i64 @"$ss12_ArrayBufferV013getAssociatedB0s011_ContiguousaB0VyxGSgyF"(ptr %0, ptr %Element)
  %15 = icmp eq i64 %14, 0
  br i1 %15, label %18, label %16

16:                                               ; preds = %tagged-cont
  %17 = inttoptr i64 %14 to ptr
  br label %25

18:                                               ; preds = %tagged-cont
  %19 = call ptr @swift_bridgeObjectRetain(ptr returned %0) #3
  call void @llvm.lifetime.start.p0(i64 8, ptr %1)
  %._storage = getelementptr inbounds %Ts12_ArrayBufferV, ptr %1, i32 0, i32 0
  %._storage.rawValue = getelementptr inbounds %Ts14_BridgeStorageV, ptr %._storage, i32 0, i32 0
  store ptr %0, ptr %._storage.rawValue, align 8
  %20 = call swiftcc %swift.metadata_response @"$ss12_ArrayBufferVMa"(i64 0, ptr %Element) #14
  %21 = extractvalue %swift.metadata_response %20, 0
  %22 = call ptr @swift_getWitnessTable(ptr @"$ss12_ArrayBufferVyxGSTsMc", ptr %21, ptr undef) #12
  %23 = call swiftcc ptr @"$ss15ContiguousArrayVyAByxGqd__c7ElementQyd__RszSTRd__lufC"(ptr noalias %1, ptr %Element, ptr %21, ptr %22)
  call void @llvm.lifetime.end.p0(i64 8, ptr %1)
  %24 = call ptr @swift_retain(ptr returned %23) #6
  call swiftcc void @"$ss12_ArrayBufferV013setAssociatedB0yys011_ContiguousaB0VyxGF"(ptr %23, ptr %0, ptr %Element)
  br label %28

25:                                               ; preds = %16
  %26 = phi ptr [ %17, %16 ]
  %27 = call ptr @swift_retain(ptr returned %26) #6
  br label %28

28:                                               ; preds = %25, %18
  %29 = phi ptr [ %23, %18 ], [ %26, %25 ]
  %30 = phi ptr [ %23, %18 ], [ %26, %25 ]
  %31 = call i32 @objc_sync_exit(ptr %12)
  call swiftcc void @"$ss12_ArrayBufferV029getOrAllocateAssociatedObjectB0s011_ContiguousaB0VyxGyF6$deferL_yylF"(ptr %29, ptr %Element)
  call void @swift_release(ptr %29) #3
  br label %34

32:                                               ; preds = %4
  %33 = phi ptr [ %5, %4 ]
  br label %34

34:                                               ; preds = %32, %28
  %35 = phi ptr [ %30, %28 ], [ %33, %32 ]
  ret ptr %35
}

declare swiftcc ptr @"$ss22_ContiguousArrayBufferV19firstElementAddressSpyxGvg"(ptr, ptr) #0

define linkonce_odr hidden swiftcc i64 @"$ss12_ArrayBufferV013getAssociatedB0s011_ContiguousaB0VyxGSgyF"(ptr %0, ptr %Element) #0 {
entry:
  %Element1 = alloca ptr, align 8
  %bitcast = alloca %TSv, align 8
  store ptr %Element, ptr %Element1, align 8
  %1 = call ptr @getGetAssociatedObjectPtr()
  call void @llvm.lifetime.start.p0(i64 8, ptr %bitcast)
  %bitcast._rawValue = getelementptr inbounds %TSv, ptr %bitcast, i32 0, i32 0
  store ptr %1, ptr %bitcast._rawValue, align 8
  %2 = load ptr, ptr %bitcast, align 8
  call void @llvm.lifetime.end.p0(i64 8, ptr %bitcast)
  %3 = ptrtoint ptr %0 to i64
  %4 = and i64 %3, -9223372036854775808
  %5 = icmp eq i64 %4, 0
  br i1 %5, label %not-tagged-pointer, label %tagged-pointer

tagged-pointer:                                   ; preds = %entry
  br label %tagged-cont

not-tagged-pointer:                               ; preds = %entry
  %6 = and i64 %3, 1152921504606846968
  %7 = inttoptr i64 %6 to ptr
  br label %tagged-cont

tagged-cont:                                      ; preds = %not-tagged-pointer, %tagged-pointer
  %8 = phi ptr [ %0, %tagged-pointer ], [ %7, %not-tagged-pointer ]
  %9 = call swiftcc ptr @"$ss12_ArrayBufferV14associationKeySVvgZ"(ptr %Element)
  %10 = call ptr %2(ptr %8, ptr %9)
  %11 = ptrtoint ptr %10 to i64
  %12 = icmp eq i64 %11, 0
  br i1 %12, label %15, label %13

13:                                               ; preds = %tagged-cont
  %14 = inttoptr i64 %11 to ptr
  br label %16

15:                                               ; preds = %tagged-cont
  br label %21

16:                                               ; preds = %13
  %17 = phi ptr [ %14, %13 ]
  %18 = call ptr @swift_retain(ptr returned %17) #6
  %19 = call swiftcc ptr @"$ss22_ContiguousArrayBufferVyAByxGs02__aB11StorageBaseCcfC"(ptr %17, ptr %Element)
  %20 = ptrtoint ptr %19 to i64
  br label %21

21:                                               ; preds = %16, %15
  %22 = phi i64 [ 0, %15 ], [ %20, %16 ]
  ret i64 %22
}

declare i32 @objc_sync_enter(ptr noundef) #0

declare swiftcc ptr @"$ss15ContiguousArrayVyAByxGqd__c7ElementQyd__RszSTRd__lufC"(ptr noalias, ptr, ptr, ptr) #0

declare swiftcc %swift.metadata_response @"$ss12_ArrayBufferVMa"(i64, ptr) #0

; Function Attrs: nounwind memory(read)
declare ptr @swift_getWitnessTable(ptr, ptr, ptr) #12

define linkonce_odr hidden swiftcc void @"$ss12_ArrayBufferV013setAssociatedB0yys011_ContiguousaB0VyxGF"(ptr %0, ptr %1, ptr %Element) #0 {
entry:
  %Element1 = alloca ptr, align 8
  %bitcast = alloca %TSv, align 8
  store ptr %Element, ptr %Element1, align 8
  %2 = call ptr @getSetAssociatedObjectPtr()
  call void @llvm.lifetime.start.p0(i64 8, ptr %bitcast)
  %bitcast._rawValue = getelementptr inbounds %TSv, ptr %bitcast, i32 0, i32 0
  store ptr %2, ptr %bitcast._rawValue, align 8
  %3 = load ptr, ptr %bitcast, align 8
  call void @llvm.lifetime.end.p0(i64 8, ptr %bitcast)
  %4 = ptrtoint ptr %1 to i64
  %5 = and i64 %4, -9223372036854775808
  %6 = icmp eq i64 %5, 0
  br i1 %6, label %not-tagged-pointer, label %tagged-pointer

tagged-pointer:                                   ; preds = %entry
  br label %tagged-cont

not-tagged-pointer:                               ; preds = %entry
  %7 = and i64 %4, 1152921504606846968
  %8 = inttoptr i64 %7 to ptr
  br label %tagged-cont

tagged-cont:                                      ; preds = %not-tagged-pointer, %tagged-pointer
  %9 = phi ptr [ %1, %tagged-pointer ], [ %8, %not-tagged-pointer ]
  %10 = call swiftcc ptr @"$ss12_ArrayBufferV14associationKeySVvgZ"(ptr %Element)
  %11 = ptrtoint ptr %0 to i64
  %12 = inttoptr i64 %11 to ptr
  call void %3(ptr %9, ptr %10, ptr %12, i64 1)
  ret void
}

declare i32 @objc_sync_exit(ptr noundef) #0

define linkonce_odr hidden swiftcc void @"$ss12_ArrayBufferV029getOrAllocateAssociatedObjectB0s011_ContiguousaB0VyxGyF6$deferL_yylF"(ptr %0, ptr %Element) #0 {
entry:
  %Element1 = alloca ptr, align 8
  store ptr %Element, ptr %Element1, align 8
  ret void
}

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define internal ptr @getSetAssociatedObjectPtr() #13 {
entry:
  ret ptr @objc_setAssociatedObject
}

define linkonce_odr hidden swiftcc ptr @"$ss12_ArrayBufferV14associationKeySVvgZ"(ptr %Element) #0 {
entry:
  %Element1 = alloca ptr, align 8
  store ptr %Element, ptr %Element1, align 8
  ret ptr @_swiftEmptyArrayStorage
}

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define internal ptr @getGetAssociatedObjectPtr() #13 {
entry:
  ret ptr @objc_getAssociatedObject
}

declare swiftcc ptr @"$ss22_ContiguousArrayBufferVyAByxGs02__aB11StorageBaseCcfC"(ptr, ptr) #0

declare swiftcc %swift.metadata_response @"$sSaMa"(i64, ptr) #0

declare void @objc_setAssociatedObject() #0

declare void @objc_getAssociatedObject() #0

attributes #0 = { "frame-pointer"="non-leaf" "no-trapping-math"="true" "probe-stack"="__chkstk_darwin" "stack-protector-buffer-size"="8" "target-cpu"="apple-a12" "target-features"="+aes,+ccidx,+complxnum,+crc,+fp-armv8,+fullfp16,+jsconv,+lse,+neon,+pauth,+perfmon,+ras,+rcpc,+rdm,+sha2,+v8.1a,+v8.2a,+v8.3a,+v8a,+zcm,+zcz" }
attributes #1 = { noinline "frame-pointer"="non-leaf" "no-trapping-math"="true" "probe-stack"="__chkstk_darwin" "stack-protector-buffer-size"="8" "target-cpu"="apple-a12" "target-features"="+aes,+ccidx,+complxnum,+crc,+fp-armv8,+fullfp16,+jsconv,+lse,+neon,+pauth,+perfmon,+ras,+rcpc,+rdm,+sha2,+v8.1a,+v8.2a,+v8.3a,+v8a,+zcm,+zcz" }
attributes #2 = { nocallback nofree nosync nounwind willreturn memory(argmem: readwrite) }
attributes #3 = { nounwind }
attributes #4 = { nocallback nofree nounwind willreturn memory(argmem: write) }
attributes #5 = { noinline nounwind memory(none) "frame-pointer"="non-leaf" "no-trapping-math"="true" "probe-stack"="__chkstk_darwin" "stack-protector-buffer-size"="8" "target-cpu"="apple-a12" "target-features"="+aes,+ccidx,+complxnum,+crc,+fp-armv8,+fullfp16,+jsconv,+lse,+neon,+pauth,+perfmon,+ras,+rcpc,+rdm,+sha2,+v8.1a,+v8.2a,+v8.3a,+v8a,+zcm,+zcz" }
attributes #6 = { nounwind willreturn }
attributes #7 = { noinline nounwind "frame-pointer"="non-leaf" "no-trapping-math"="true" "probe-stack"="__chkstk_darwin" "stack-protector-buffer-size"="8" "target-cpu"="apple-a12" "target-features"="+aes,+ccidx,+complxnum,+crc,+fp-armv8,+fullfp16,+jsconv,+lse,+neon,+pauth,+perfmon,+ras,+rcpc,+rdm,+sha2,+v8.1a,+v8.2a,+v8.3a,+v8a,+zcm,+zcz" }
attributes #8 = { nounwind willreturn memory(none) }
attributes #9 = { noinline nounwind willreturn memory(read) "frame-pointer"="non-leaf" "no-trapping-math"="true" "probe-stack"="__chkstk_darwin" "stack-protector-buffer-size"="8" "target-cpu"="apple-a12" "target-features"="+aes,+ccidx,+complxnum,+crc,+fp-armv8,+fullfp16,+jsconv,+lse,+neon,+pauth,+perfmon,+ras,+rcpc,+rdm,+sha2,+v8.1a,+v8.2a,+v8.3a,+v8a,+zcm,+zcz" }
attributes #10 = { nounwind memory(argmem: readwrite) }
attributes #11 = { nocallback nofree nosync nounwind willreturn memory(none) }
attributes #12 = { nounwind memory(read) }
attributes #13 = { noinline nounwind optnone ssp uwtable(sync) "frame-pointer"="non-leaf" "no-trapping-math"="true" "probe-stack"="__chkstk_darwin" "stack-protector-buffer-size"="8" "target-cpu"="apple-a12" "target-features"="+aes,+ccidx,+complxnum,+crc,+fp-armv8,+fullfp16,+jsconv,+lse,+neon,+pauth,+perfmon,+ras,+rcpc,+rdm,+sha2,+v8.1a,+v8.2a,+v8.3a,+v8a,+zcm,+zcz" }
attributes #14 = { nounwind memory(none) }
attributes #15 = { noinline }
attributes #16 = { nounwind memory(argmem: read) }

!llvm.module.flags = !{!0, !1, !2, !3, !4, !5, !6, !7, !8, !9, !10, !11}
!swift.module.flags = !{!12}
!llvm.linker.options = !{!13, !14, !15, !16, !17, !18, !19, !20, !21, !22, !23, !24, !25, !26, !27, !28, !29, !30, !31, !32, !33, !34, !35, !36, !37, !38}

!0 = !{i32 2, !"SDK Version", [2 x i32] [i32 26, i32 2]}
!1 = !{i32 1, !"Objective-C Version", i32 2}
!2 = !{i32 1, !"Objective-C Image Info Version", i32 0}
!3 = !{i32 1, !"Objective-C Image Info Section", !"__DATA,__objc_imageinfo,regular,no_dead_strip"}
!4 = !{i32 4, !"Objective-C Garbage Collection", i32 100796160}
!5 = !{i32 1, !"Objective-C Class Properties", i32 64}
!6 = !{i32 1, !"Objective-C Enforce ClassRO Pointer Signing", i8 0}
!7 = !{i32 1, !"wchar_size", i32 4}
!8 = !{i32 8, !"PIC Level", i32 2}
!9 = !{i32 7, !"uwtable", i32 1}
!10 = !{i32 7, !"frame-pointer", i32 1}
!11 = !{i32 1, !"Swift Version", i32 7}
!12 = !{!"standard-library", i1 false}
!13 = !{!"-lswiftFoundation"}
!14 = !{!"-framework", !"Foundation"}
!15 = !{!"-lswiftCore"}
!16 = !{!"-lswift_DarwinFoundation3"}
!17 = !{!"-lswift_DarwinFoundation1"}
!18 = !{!"-lswift_DarwinFoundation2"}
!19 = !{!"-lswift_StringProcessing"}
!20 = !{!"-lswift_Concurrency"}
!21 = !{!"-lswiftSystem"}
!22 = !{!"-lswiftDarwin"}
!23 = !{!"-lswift_Builtin_float"}
!24 = !{!"-lswiftObservation"}
!25 = !{!"-lswiftObjectiveC"}
!26 = !{!"-lswiftCoreFoundation"}
!27 = !{!"-framework", !"CoreFoundation"}
!28 = !{!"-lswiftDispatch"}
!29 = !{!"-framework", !"Combine"}
!30 = !{!"-framework", !"CoreServices"}
!31 = !{!"-framework", !"Security"}
!32 = !{!"-lswiftXPC"}
!33 = !{!"-framework", !"CFNetwork"}
!34 = !{!"-framework", !"DiskArbitration"}
!35 = !{!"-lswiftIOKit"}
!36 = !{!"-framework", !"IOKit"}
!37 = !{!"-lswiftSwiftOnoneSupport"}
!38 = !{!"-lobjc"}
!39 = !{}
!40 = !{i64 88}
