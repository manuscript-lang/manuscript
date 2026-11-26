// conform: tags=diagnostics,parser,tier-core
// conform: phase=parse
// conform: origin=foreign-syntax diagnostics
fn f() Void {
    del items
}
// expect-error: MS1000 5:5-5:8 'del' is not a keyword; remove from a collection with its methods, such as xs.remove(i) or m.remove(key)
// expect-format-exit: 1
