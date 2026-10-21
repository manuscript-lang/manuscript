target triple = "x86_64-unknown-linux-gnu"
define hidden i64 @"collatz#0"(i64 %a0) #0 {
b0:
  br label %e0
b1:
  %p1_0 = phi i64 [ 1, %e0 ], [ %t39, %e3 ]
  %p1_1 = phi i64 [ 0, %e0 ], [ %t38, %e3 ]
  %t1 = icmp slt i64 %p1_0, %a0
  %t2 = zext i1 %t1 to i8
  %t3 = icmp sge i64 %p1_0, %a0
  %t4 = zext i1 %t3 to i8
  %t5 = icmp ne i8 %t4, 0
  br i1 %t5, label %b5, label %e1
b2:
  %p2_0 = phi i64 [ %p1_0, %e1 ], [ %t33, %e2 ]
  %p2_1 = phi i64 [ 0, %e1 ], [ %t34, %e2 ]
  %t6 = ptrtoint ptr @"msrt_cancel_flag" to i64
  %t7 = inttoptr i64 %t6 to ptr
  %t8 = load atomic i8, ptr %t7 monotonic, align 1
  %t9 = icmp ne i8 %t8, 0
  br i1 %t9, label %b6, label %b7
b6:
  call void @"msrt_cancelled"()
  call void @llvm.trap()
  unreachable
b7:
  %t10 = icmp ne i64 %p2_0, 1
  %t11 = zext i1 %t10 to i8
  %t12 = icmp ne i8 %t11, 0
  br i1 %t12, label %b3, label %b4
b3:
  %t13 = and i64 %p2_0, 1
  %t14 = icmp eq i64 %t13, 0
  %t15 = zext i1 %t14 to i8
  %t16 = sdiv i64 %p2_0, 2
  %t17 = xor i8 %t15, 1
  %t18 = add i64 %p2_0, 3074457345618258602
  %t19 = icmp ugt i64 %t18, 6148914691236517204
  %t20 = zext i1 %t19 to i8
  %t21 = and i64 1, 63
  %t22 = shl i64 %p2_0, %t21
  %t23 = add i64 %p2_0, %t22
  %t24 = and i8 %t17, %t20
  %t25 = call { i64, i1 } @llvm.sadd.with.overflow.i64(i64 %t23, i64 1)
  %t26 = extractvalue { i64, i1 } %t25, 0
  %t27 = extractvalue { i64, i1 } %t25, 1
  %t28 = zext i1 %t27 to i8
  %t29 = and i8 %t17, %t28
  %t30 = icmp ne i8 %t24, 0
  br i1 %t30, label %b8, label %b9
b8:
  call void @"msrt_fault_int_overflow"()
  call void @llvm.trap()
  unreachable
b9:
  %t31 = icmp ne i8 %t29, 0
  br i1 %t31, label %b10, label %b11
b10:
  call void @"msrt_fault_int_overflow"()
  call void @llvm.trap()
  unreachable
b11:
  %t32 = icmp ne i8 %t15, 0
  %t33 = select i1 %t32, i64 %t16, i64 %t26
  %t34 = add i64 %p2_1, 1
  br label %e2
b4:
  %t35 = icmp sgt i64 %p2_1, %p1_1
  %t36 = zext i1 %t35 to i8
  %t37 = icmp ne i8 %t36, 0
  %t38 = select i1 %t37, i64 %p2_1, i64 %p1_1
  %t39 = add i64 %p1_0, 1
  br label %e3
b5:
  ret i64 %p1_1
e0:
  br label %b1
e1:
  br label %b2
e2:
  br label %b2
e3:
  br label %b1
}

define i64 @"ms_entry"() #0 {
b0:
  %t1 = call i64 @"collatz#0"(i64 1000000)
  call void @"msrt_print_int"(i64 %t1)
  ret i64 0
}

declare void @"msrt_cancelled"()
declare void @"msrt_fault_int_overflow"()
declare void @"msrt_print_int"(i64)
@"msrt_cancel_flag" = external global i8
declare void @llvm.trap() cold noreturn nounwind
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
