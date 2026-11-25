// conform: tags=diagnostics,parser,tier-core
// conform: phase=parse
// conform: origin=foreign-syntax diagnostics
fn f() Void {
    class Point {
    }
}
// expect-error: MS1000 5:5-5:10 'class' is not a keyword inside a fn; declare a type with 'type Name { ... }' at module level
// expect-format-exit: 1
