// conform: tags=diagnostics,tier-core
// conform: phase=check
// conform: origin=pkg/build/expression_conveniences_test.go:15 TestExpressionConvenienceRejections
fn f() Int => return 1 [0]
// expect-error: MS3000 4:22 indexing requires List[T], Map[K, V] or Bytes; use the receiver's lookup method for other types
