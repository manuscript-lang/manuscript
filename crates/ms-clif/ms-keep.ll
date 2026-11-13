target triple = "x86_64-unknown-linux-gnu"
define void @"ms.text.base"() #0 {
  ret void
}

define internal i64 @"drain#0"(i64 %a0_0) #0 !dbg !6 {
b0:
  %v1 = add i64 %a0_0, 1, !dbg !8
  %v2 = call noalias align 16 ptr @"msrt_alloc"(i64 16), !dbg !9
  %v6 = getelementptr inbounds i64, ptr %v2, i64 0, !dbg !9
  store i64 %a0_0, ptr %v6, align 8, !tbaa !1073741827, !dbg !9
  %v7 = getelementptr inbounds i64, ptr %v2, i64 1, !dbg !9
  store i64 %v1, ptr %v7, align 8, !tbaa !1073741827, !dbg !9
  %v3 = sub i64 2, 1, !dbg !9
  %v8 = getelementptr inbounds i64, ptr %v2, i64 %v3, !dbg !10
  %v4 = load i64, ptr %v8, align 8, !tbaa !1073741827, !dbg !10
  %v5 = add i64 2, -1, !dbg !11
  %v9 = icmp ne i64 2, 0, !dbg !12
  %v10 = icmp ne ptr %v2, null, !dbg !12
  %v11 = and i1 %v9, %v10, !dbg !12
  br i1 %v11, label %e0_0, label %b0.1, !dbg !12
e0_0:
  %v12 = ptrtoint ptr %v2 to i64, !dbg !12
  call void @"msrt_free"(i64 %v12), !dbg !12
  br label %b0.1, !dbg !12
b0.1:
  ret i64 %v4, !dbg !7
}

define i64 @"ms_entry"() #0 !dbg !13 {
b0:
  %v1 = call i64 @"drain#0"(i64 34) nomerge, !dbg !16
  ret i64 %v1, !dbg !14
}

declare noalias align 16 ptr @"msrt_alloc"(i64) nounwind
declare void @"msrt_free"(i64) nounwind
declare void @llvm.trap() cold noreturn nounwind
declare void @llvm.memcpy.p0.p0.i64(ptr, ptr, i64, i1)
declare void @llvm.memmove.p0.p0.i64(ptr, ptr, i64, i1)
declare void @llvm.memset.p0.i64(ptr, i8, i64, i1)
declare ptr @llvm.frameaddress.p0(i32)
declare ptr @llvm.ptrmask.p0.i64(ptr, i64) nounwind speculatable willreturn memory(none)
declare double @llvm.fabs.f64(double)
declare double @llvm.sqrt.f64(double)
declare double @llvm.floor.f64(double)
declare double @llvm.ceil.f64(double)
declare double @llvm.trunc.f64(double)
declare float @llvm.fabs.f32(float)
declare float @llvm.sqrt.f32(float)
declare float @llvm.floor.f32(float)
declare float @llvm.ceil.f32(float)
declare float @llvm.trunc.f32(float)
declare i64 @llvm.fptosi.sat.i64.f64(double)
declare i64 @llvm.fptosi.sat.i64.f32(float)
declare i64 @llvm.fshl.i64(i64, i64, i64)
declare i64 @llvm.fshr.i64(i64, i64, i64)
declare i64 @llvm.ctlz.i64(i64, i1)
declare i64 @llvm.cttz.i64(i64, i1)
declare i64 @llvm.ctpop.i64(i64)
declare { i64, i1 } @llvm.sadd.with.overflow.i64(i64, i64)
declare { i32, i1 } @llvm.sadd.with.overflow.i32(i32, i32)
declare { i8, i1 } @llvm.sadd.with.overflow.i8(i8, i8)
declare { i64, i1 } @llvm.ssub.with.overflow.i64(i64, i64)
declare { i32, i1 } @llvm.ssub.with.overflow.i32(i32, i32)
declare { i8, i1 } @llvm.ssub.with.overflow.i8(i8, i8)
declare { i64, i1 } @llvm.smul.with.overflow.i64(i64, i64)
declare { i32, i1 } @llvm.smul.with.overflow.i32(i32, i32)
declare { i8, i1 } @llvm.smul.with.overflow.i8(i8, i8)
declare { i64, i1 } @llvm.uadd.with.overflow.i64(i64, i64)
declare { i32, i1 } @llvm.uadd.with.overflow.i32(i32, i32)
declare { i8, i1 } @llvm.uadd.with.overflow.i8(i8, i8)
declare { i64, i1 } @llvm.usub.with.overflow.i64(i64, i64)
declare { i32, i1 } @llvm.usub.with.overflow.i32(i32, i32)
declare { i8, i1 } @llvm.usub.with.overflow.i8(i8, i8)
declare { i64, i1 } @llvm.umul.with.overflow.i64(i64, i64)
declare { i32, i1 } @llvm.umul.with.overflow.i32(i32, i32)
declare { i8, i1 } @llvm.umul.with.overflow.i8(i8, i8)
attributes #0 = { "frame-pointer"="all" nounwind }
attributes #1 = { "frame-pointer"="all" nounwind noinline }
attributes #4 = { "frame-pointer"="all" nounwind noinline optnone }
attributes #5 = { "frame-pointer"="all" nounwind optsize }
attributes #2 = { "frame-pointer"="all" nounwind noimplicitfloat }
!llvm.dbg.cu = !{!0}
!llvm.module.flags = !{!1, !2}
!0 = distinct !DICompileUnit(language: DW_LANG_C99, file: !5, producer: "Manuscript", isOptimized: true, runtimeVersion: 0, emissionKind: LineTablesOnly)
!1 = !{i32 2, !"Debug Info Version", i32 3}
!2 = !{i32 7, !"Dwarf Version", i32 4}
!3 = !{}
!4 = !DISubroutineType(types: !3)
!1073741824 = !{!"ms.tbaa"}
!1073741825 = !{!"ms.scalar-elem", !1073741824, i64 0}
!1073741826 = !{!"ms.header-elem", !1073741824, i64 0}
!1073741827 = !{!1073741825, !1073741825, i64 0}
!1073741828 = !{!1073741826, !1073741826, i64 0}
!1073741829 = !{i8 0, i8 2}
!1073741830 = !{i64 0, i64 -9223372036854775808}
!1073741831 = !{i64 8}
!5 = !DIFile(filename: "d.ms", directory: "/home/user/manuscript/crates/ms-clif")
!6 = distinct !DISubprogram(name: "drain", linkageName: "drain#0", scope: !5, file: !5, line: 1, type: !4, scopeLine: 1, spFlags: DISPFlagDefinition, unit: !0)
!7 = !DILocation(line: 0, scope: !6)
!8 = !DILocation(line: 2, scope: !6)
!9 = !DILocation(line: 3, scope: !6)
!10 = !DILocation(line: 4, scope: !6)
!11 = !DILocation(line: 5, scope: !6)
!12 = !DILocation(line: 6, scope: !6)
!13 = distinct !DISubprogram(name: "main", linkageName: "ms_entry", scope: !5, file: !5, line: 10, type: !4, scopeLine: 10, spFlags: DISPFlagDefinition, unit: !0)
!14 = !DILocation(line: 0, scope: !13)
!15 = !DILocation(line: 11, scope: !13)
!16 = !DILocation(line: 12, scope: !13)
