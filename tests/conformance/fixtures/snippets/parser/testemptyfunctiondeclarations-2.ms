// conform: tags=closures,diagnostics,formatter,generics,interfaces,lists,records,tier-core
// conform: phase=check,parse
// conform: origin=pkg/parser/empty_declarations_test.go:12 TestEmptyFunctionDeclarations
type List[T] { ... }

fn List[T].map[U](transform fn(T) U) List[U] { ... }

fn List[T].length() Int { ... }
// expect-error: MS2001 4:1 declaration List reuses a prelude name; rename it, because List always refers to the standard declaration
// expect-error: MS3012 6:1 implementation receiver must be nominal source data; declare methods on a type or enum you declare, such as 'fn Point.show() String { ... }', not on built-in or function types
