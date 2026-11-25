// conform: tags=diagnostics
// conform: phase=check
fn f() Int => return 1 [0]
// expect-error: MS3000 3:22 indexing requires List[T], Map[K, V] or Bytes; use the receiver's lookup method for other types
