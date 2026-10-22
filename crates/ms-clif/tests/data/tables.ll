target triple = "x86_64-unknown-linux-gnu"
define i64 @"ms_entry"() #0 !dbg !6 {
b0:
  %t1 = call i64 @"sum_squares#1"(i64 20), !dbg !8
  %t2 = call i64 @"msrt_alloc"(i64 1), !dbg !9
  %t3 = ptrtoint ptr @"ms.vtable.0.vtable_stdout_0" to i64, !dbg !9
  %t4 = icmp sgt i64 %t1, 100, !dbg !13
  %t5 = zext i1 %t4 to i8, !dbg !13
  %t6 = icmp ne i8 %t5, 0, !dbg !13
  br i1 %t6, label %b1, label %b2, !dbg !13
b1:
  %t7 = ptrtoint ptr @"ms.str.0" to i64, !dbg !14
  %t8 = call i64 @"msrt_int_to_string"(i64 %t1), !dbg !14
  %t9 = call i64 @"msrt_string_concat"(i64 %t7, i64 %t8), !dbg !14
  %t10 = ptrtoint ptr @"ms.str.1" to i64, !dbg !14
  %t11 = call i64 @"msrt_string_concat"(i64 %t9, i64 %t10), !dbg !14
  %t12 = inttoptr i64 %t9 to ptr, !dbg !14
  %t13 = load i64, ptr %t12, align 8, !dbg !14
  %t14 = add i64 %t13, -1, !dbg !14
  %t15 = inttoptr i64 %t9 to ptr, !dbg !14
  store i64 %t14, ptr %t15, align 8, !dbg !14
  %t16 = icmp eq i64 %t14, 0, !dbg !14
  %t17 = zext i1 %t16 to i8, !dbg !14
  %t18 = icmp ne i8 %t17, 0, !dbg !14
  br i1 %t18, label %b4, label %b5, !dbg !14
b4:
  call void @"msrt_drop_slow"(i64 %t9), !dbg !14
  br label %b5, !dbg !14
b5:
  %t19 = inttoptr i64 %t8 to ptr, !dbg !14
  %t20 = load i64, ptr %t19, align 8, !dbg !14
  %t21 = add i64 %t20, -1, !dbg !14
  %t22 = inttoptr i64 %t8 to ptr, !dbg !14
  store i64 %t21, ptr %t22, align 8, !dbg !14
  %t23 = icmp eq i64 %t21, 0, !dbg !14
  %t24 = zext i1 %t23 to i8, !dbg !14
  %t25 = icmp ne i8 %t24, 0, !dbg !14
  br i1 %t25, label %b6, label %b7, !dbg !14
b6:
  call void @"msrt_drop_slow"(i64 %t8), !dbg !14
  br label %b7, !dbg !14
b7:
  br label %e0, !dbg !14
b2:
  %t26 = ptrtoint ptr @"ms.str.2" to i64, !dbg !15
  %t27 = call i64 @"msrt_int_to_string"(i64 %t1), !dbg !15
  %t28 = call i64 @"msrt_string_concat"(i64 %t26, i64 %t27), !dbg !15
  %t29 = ptrtoint ptr @"ms.str.1" to i64, !dbg !15
  %t30 = call i64 @"msrt_string_concat"(i64 %t28, i64 %t29), !dbg !15
  %t31 = inttoptr i64 %t28 to ptr, !dbg !15
  %t32 = load i64, ptr %t31, align 8, !dbg !15
  %t33 = add i64 %t32, -1, !dbg !15
  %t34 = inttoptr i64 %t28 to ptr, !dbg !15
  store i64 %t33, ptr %t34, align 8, !dbg !15
  %t35 = icmp eq i64 %t33, 0, !dbg !15
  %t36 = zext i1 %t35 to i8, !dbg !15
  %t37 = icmp ne i8 %t36, 0, !dbg !15
  br i1 %t37, label %b8, label %b9, !dbg !15
b8:
  call void @"msrt_drop_slow"(i64 %t28), !dbg !15
  br label %b9, !dbg !15
b9:
  %t38 = inttoptr i64 %t27 to ptr, !dbg !15
  %t39 = load i64, ptr %t38, align 8, !dbg !15
  %t40 = add i64 %t39, -1, !dbg !15
  %t41 = inttoptr i64 %t27 to ptr, !dbg !15
  store i64 %t40, ptr %t41, align 8, !dbg !15
  %t42 = icmp eq i64 %t40, 0, !dbg !15
  %t43 = zext i1 %t42 to i8, !dbg !15
  %t44 = icmp ne i8 %t43, 0, !dbg !15
  br i1 %t44, label %b10, label %b11, !dbg !15
b10:
  call void @"msrt_drop_slow"(i64 %t27), !dbg !15
  br label %b11, !dbg !15
b11:
  br label %e1, !dbg !15
b3:
  %p3_0 = phi i64 [ %t11, %e0 ], [ %t30, %e1 ]
  %t45 = inttoptr i64 %t3 to ptr, !dbg !9
  %t46 = getelementptr inbounds i8, ptr %t45, i64 24, !dbg !9
  %t47 = load i64, ptr %t46, align 8, !dbg !9
  %t48 = inttoptr i64 %t47 to ptr, !dbg !9
  %t49 = call { i64, i64, i64 } %t48(i64 %t2, i64 %p3_0), !dbg !9
  %t50 = extractvalue { i64, i64, i64 } %t49, 0, !dbg !9
  %t51 = extractvalue { i64, i64, i64 } %t49, 1, !dbg !9
  %t52 = extractvalue { i64, i64, i64 } %t49, 2, !dbg !9
  %t53 = icmp eq i64 %t50, 1, !dbg !9
  %t54 = zext i1 %t53 to i8, !dbg !9
  call void @"ms.glue.2.drop"(i64 %t50, i64 %t51, i64 %t52), !dbg !9
  call void @"ms.glue.3.drop"(i64 %t2, i64 %t3), !dbg !9
  %t55 = inttoptr i64 %p3_0 to ptr, !dbg !9
  %t56 = load i64, ptr %t55, align 8, !dbg !9
  %t57 = add i64 %t56, -1, !dbg !9
  %t58 = inttoptr i64 %p3_0 to ptr, !dbg !9
  store i64 %t57, ptr %t58, align 8, !dbg !9
  %t59 = icmp eq i64 %t57, 0, !dbg !9
  %t60 = zext i1 %t59 to i8, !dbg !9
  %t61 = icmp ne i8 %t60, 0, !dbg !9
  br i1 %t61, label %b12, label %b13, !dbg !9
b12:
  call void @"msrt_drop_slow"(i64 %p3_0), !dbg !9
  br label %b13, !dbg !9
b13:
  %t62 = icmp ne i8 %t54, 0, !dbg !9
  %t63 = select i1 %t62, i64 1, i64 0, !dbg !9
  ret i64 %t63, !dbg !17
e0:
  br label %b3
e1:
  br label %b3
}

define hidden i64 @"sum_squares#1"(i64 %a0) #0 !dbg !18 {
b0:
  br label %e0, !dbg !21
b1:
  %p1_0 = phi i64 [ 0, %e0 ], [ %t16, %e1 ]
  %p1_1 = phi i64 [ 0, %e0 ], [ %t12, %e1 ]
  %t1 = icmp slt i64 %p1_0, %a0, !dbg !21
  %t2 = zext i1 %t1 to i8, !dbg !21
  %t3 = icmp sge i64 %p1_0, %a0, !dbg !21
  %t4 = zext i1 %t3 to i8, !dbg !21
  %t5 = icmp ne i8 %t4, 0, !dbg !21
  br i1 %t5, label %b3, label %b2, !dbg !21
b2:
  %t6 = call { i64, i1 } @llvm.smul.with.overflow.i64(i64 %p1_0, i64 %p1_0), !dbg !25
  %t7 = extractvalue { i64, i1 } %t6, 0, !dbg !25
  %t8 = extractvalue { i64, i1 } %t6, 1, !dbg !25
  %t9 = zext i1 %t8 to i8, !dbg !25
  %t10 = icmp ne i8 %t9, 0, !dbg !25
  br i1 %t10, label %b4, label %b5, !dbg !25
b4:
  call void asm sideeffect "", "i"(i32 1), !dbg !25
  call void @"msrt_fault_int_overflow"(), !dbg !25
  call void @llvm.trap(), !dbg !25
  unreachable, !dbg !25
b5:
  %t11 = call { i64, i1 } @llvm.sadd.with.overflow.i64(i64 %p1_1, i64 %t7), !dbg !26
  %t12 = extractvalue { i64, i1 } %t11, 0, !dbg !26
  %t13 = extractvalue { i64, i1 } %t11, 1, !dbg !26
  %t14 = zext i1 %t13 to i8, !dbg !26
  %t15 = icmp ne i8 %t14, 0, !dbg !26
  br i1 %t15, label %b6, label %b7, !dbg !26
b6:
  call void asm sideeffect "", "i"(i32 2), !dbg !26
  call void @"msrt_fault_int_overflow"(), !dbg !26
  call void @llvm.trap(), !dbg !26
  unreachable, !dbg !26
b7:
  %t16 = add i64 %p1_0, 1, !dbg !27
  br label %e1, !dbg !21
b3:
  ret i64 %p1_1, !dbg !28
e0:
  br label %b1
e1:
  br label %b1
}

define hidden void @"stream.close#2"(i64 %a0) #0 !dbg !29 {
b0:
  ret void, !dbg !30
}

define hidden { i64, i64, i64 } @"stream.flush#3"(i64 %a0) #0 !dbg !31 {
b0:
  call void @"msrt_io_flush"(), !dbg !32
  %t1 = insertvalue { i64, i64, i64 } undef, i64 0, 0, !dbg !32
  %t2 = insertvalue { i64, i64, i64 } %t1, i64 0, 1, !dbg !32
  %t3 = insertvalue { i64, i64, i64 } %t2, i64 0, 2, !dbg !32
  ret { i64, i64, i64 } %t3, !dbg !32
}

define hidden { i64, i64, i64 } @"stream.write#4"(i64 %a0, i64 %a1) #0 !dbg !33 {
b0:
  call void @"msrt_io_write_stdout"(i64 %a1), !dbg !34
  %t1 = insertvalue { i64, i64, i64 } undef, i64 0, 0, !dbg !34
  %t2 = insertvalue { i64, i64, i64 } %t1, i64 0, 1, !dbg !34
  %t3 = insertvalue { i64, i64, i64 } %t2, i64 0, 2, !dbg !34
  ret { i64, i64, i64 } %t3, !dbg !34
}

define hidden { i64, i64, i64 } @"stream.write_bytes#5"(i64 %a0, i64 %a1, i64 %a2, i64 %a3) #0 !dbg !35 {
b0:
  %ss0 = alloca [24 x i8], align 8
  %t1 = ptrtoint ptr %ss0 to i64, !dbg !36
  %t2 = inttoptr i64 %t1 to ptr, !dbg !36
  store i64 %a1, ptr %t2, align 8, !dbg !36
  %t3 = inttoptr i64 %t1 to ptr, !dbg !36
  %t4 = getelementptr inbounds i8, ptr %t3, i64 8, !dbg !36
  store i64 %a2, ptr %t4, align 8, !dbg !36
  %t5 = inttoptr i64 %t1 to ptr, !dbg !36
  %t6 = getelementptr inbounds i8, ptr %t5, i64 16, !dbg !36
  store i64 %a3, ptr %t6, align 8, !dbg !36
  call void @"msrt_io_write_bytes_stdout"(i64 %t1), !dbg !36
  %t7 = insertvalue { i64, i64, i64 } undef, i64 0, 0, !dbg !36
  %t8 = insertvalue { i64, i64, i64 } %t7, i64 0, 1, !dbg !36
  %t9 = insertvalue { i64, i64, i64 } %t8, i64 0, 2, !dbg !36
  ret { i64, i64, i64 } %t9, !dbg !36
}

define hidden void @"ms.glue.3.drop"(i64 %a0, i64 %a1) #0 !dbg !37 {
b0:
  %t1 = inttoptr i64 %a1 to ptr, !dbg !38
  %t2 = load i64, ptr %t1, align 8, !dbg !38
  %t3 = inttoptr i64 %t2 to ptr, !dbg !38
  call void %t3(i64 %a0), !dbg !38
  ret void, !dbg !38
}

define hidden void @"ms.glue.2.drop"(i64 %a0, i64 %a1, i64 %a2) #0 !dbg !39 {
b0:
  %t1 = icmp eq i64 %a0, 1, !dbg !40
  %t2 = zext i1 %t1 to i8, !dbg !40
  %t3 = icmp ne i8 %t2, 0, !dbg !40
  br i1 %t3, label %b2, label %b3, !dbg !40
b2:
  call void @"ms.glue.4.drop"(i64 %a1, i64 %a2), !dbg !40
  br label %b1, !dbg !40
b3:
  br label %b1, !dbg !40
b1:
  ret void, !dbg !40
}

define hidden void @"ms.glue.4.drop"(i64 %a0, i64 %a1) #0 !dbg !41 {
b0:
  %t1 = icmp eq i64 %a0, 5, !dbg !42
  %t2 = zext i1 %t1 to i8, !dbg !42
  %t3 = icmp ne i8 %t2, 0, !dbg !42
  br i1 %t3, label %b2, label %b3, !dbg !42
b2:
  %t4 = inttoptr i64 %a1 to ptr, !dbg !42
  %t5 = load i64, ptr %t4, align 8, !dbg !42
  %t6 = add i64 %t5, -1, !dbg !42
  %t7 = inttoptr i64 %a1 to ptr, !dbg !42
  store i64 %t6, ptr %t7, align 8, !dbg !42
  %t8 = icmp eq i64 %t6, 0, !dbg !42
  %t9 = zext i1 %t8 to i8, !dbg !42
  %t10 = icmp ne i8 %t9, 0, !dbg !42
  br i1 %t10, label %b4, label %b5, !dbg !42
b4:
  call void @"msrt_drop_slow"(i64 %a1), !dbg !42
  br label %b5, !dbg !42
b5:
  br label %b1, !dbg !42
b3:
  br label %b1, !dbg !42
b1:
  ret void, !dbg !42
}

define hidden i64 @"ms.glue.1.block_copy"(i64 %a0) #0 !dbg !43 {
b0:
  %t1 = call i64 @"msrt_alloc"(i64 1), !dbg !44
  ret i64 %t1, !dbg !44
}

define hidden void @"ms.glue.0.block_drop"(i64 %a0) #0 !dbg !45 {
b0:
  call void @"msrt_free"(i64 %a0), !dbg !46
  ret void, !dbg !46
}

declare i64 @"msrt_alloc"(i64)
declare void @"msrt_drop_slow"(i64)
declare void @"msrt_fault_int_overflow"()
declare void @"msrt_free"(i64)
declare i64 @"msrt_int_to_string"(i64)
declare void @"msrt_io_flush"()
declare void @"msrt_io_write_bytes_stdout"(i64)
declare void @"msrt_io_write_stdout"(i64)
declare i64 @"msrt_string_concat"(i64, i64)
@"ms.str.0" = external global i8
@"ms.str.1" = external global i8
@"ms.str.2" = external global i8
@"ms.vtable.0.vtable_stdout_0" = external global i8
declare void @llvm.trap() cold noreturn nounwind
declare void @llvm.memcpy.p0.p0.i64(ptr, ptr, i64, i1)
declare void @llvm.memmove.p0.p0.i64(ptr, ptr, i64, i1)
declare void @llvm.memset.p0.i64(ptr, i8, i64, i1)
declare ptr @llvm.frameaddress.p0(i32)
declare double @llvm.fabs.f64(double)
declare double @llvm.sqrt.f64(double)
declare i64 @llvm.fptosi.sat.i64.f64(double)
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
!llvm.dbg.cu = !{!0}
!llvm.module.flags = !{!1, !2}
!0 = distinct !DICompileUnit(language: DW_LANG_C99, file: !5, producer: "Manuscript", isOptimized: true, runtimeVersion: 0, emissionKind: LineTablesOnly)
!1 = !{i32 2, !"Debug Info Version", i32 3}
!2 = !{i32 7, !"Dwarf Version", i32 4}
!3 = !{}
!4 = !DISubroutineType(types: !3)
!5 = !DIFile(filename: "src/main.ms", directory: "/work")
!6 = distinct !DISubprogram(name: "main", linkageName: "ms_entry", scope: !5, file: !5, line: 0, type: !4, scopeLine: 0, spFlags: DISPFlagDefinition, unit: !0)
!7 = !DILocation(line: 0, scope: !6)
!8 = !DILocation(line: 20, scope: !6)
!9 = !DILocation(line: 21, scope: !6)
!10 = distinct !DISubprogram(name: "describe", scope: !5, file: !5, line: 1, type: !4, scopeLine: 1, spFlags: DISPFlagDefinition, unit: !0)
!11 = !DILocation(line: 21, scope: !6)
!12 = distinct !DILexicalBlockFile(scope: !10, file: !5, discriminator: 0)
!13 = !DILocation(line: 15, scope: !12, inlinedAt: !11)
!14 = !DILocation(line: 16, scope: !12, inlinedAt: !11)
!15 = !DILocation(line: 17, scope: !12, inlinedAt: !11)
!16 = !DILocation(line: 23, scope: !6)
!17 = !DILocation(line: 22, scope: !6)
!18 = distinct !DISubprogram(name: "sum_squares", linkageName: "sum_squares#1", scope: !5, file: !5, line: 0, type: !4, scopeLine: 0, spFlags: DISPFlagDefinition, unit: !0)
!19 = !DILocation(line: 0, scope: !18)
!20 = !DILocation(line: 7, scope: !18)
!21 = !DILocation(line: 9, scope: !18)
!22 = distinct !DISubprogram(name: "square", scope: !5, file: !5, line: 1, type: !4, scopeLine: 1, spFlags: DISPFlagDefinition, unit: !0)
!23 = !DILocation(line: 10, scope: !18)
!24 = distinct !DILexicalBlockFile(scope: !22, file: !5, discriminator: 0)
!25 = !DILocation(line: 4, scope: !24, inlinedAt: !23)
!26 = !DILocation(line: 10, scope: !18)
!27 = !DILocation(line: 11, scope: !18)
!28 = !DILocation(line: 12, scope: !18)
!29 = distinct !DISubprogram(name: "stream.close", linkageName: "stream.close#2", scope: !5, file: !5, line: 0, type: !4, scopeLine: 0, spFlags: DISPFlagDefinition, unit: !0)
!30 = !DILocation(line: 0, scope: !29)
!31 = distinct !DISubprogram(name: "stream.flush", linkageName: "stream.flush#3", scope: !5, file: !5, line: 0, type: !4, scopeLine: 0, spFlags: DISPFlagDefinition, unit: !0)
!32 = !DILocation(line: 0, scope: !31)
!33 = distinct !DISubprogram(name: "stream.write", linkageName: "stream.write#4", scope: !5, file: !5, line: 0, type: !4, scopeLine: 0, spFlags: DISPFlagDefinition, unit: !0)
!34 = !DILocation(line: 0, scope: !33)
!35 = distinct !DISubprogram(name: "stream.write_bytes", linkageName: "stream.write_bytes#5", scope: !5, file: !5, line: 0, type: !4, scopeLine: 0, spFlags: DISPFlagDefinition, unit: !0)
!36 = !DILocation(line: 0, scope: !35)
!37 = distinct !DISubprogram(name: "glue", linkageName: "ms.glue.3.drop", scope: !5, file: !5, line: 0, type: !4, scopeLine: 0, spFlags: DISPFlagDefinition, unit: !0)
!38 = !DILocation(line: 0, scope: !37)
!39 = distinct !DISubprogram(name: "glue", linkageName: "ms.glue.2.drop", scope: !5, file: !5, line: 0, type: !4, scopeLine: 0, spFlags: DISPFlagDefinition, unit: !0)
!40 = !DILocation(line: 0, scope: !39)
!41 = distinct !DISubprogram(name: "glue", linkageName: "ms.glue.4.drop", scope: !5, file: !5, line: 0, type: !4, scopeLine: 0, spFlags: DISPFlagDefinition, unit: !0)
!42 = !DILocation(line: 0, scope: !41)
!43 = distinct !DISubprogram(name: "glue", linkageName: "ms.glue.1.block_copy", scope: !5, file: !5, line: 0, type: !4, scopeLine: 0, spFlags: DISPFlagDefinition, unit: !0)
!44 = !DILocation(line: 0, scope: !43)
!45 = distinct !DISubprogram(name: "glue", linkageName: "ms.glue.0.block_drop", scope: !5, file: !5, line: 0, type: !4, scopeLine: 0, spFlags: DISPFlagDefinition, unit: !0)
!46 = !DILocation(line: 0, scope: !45)
