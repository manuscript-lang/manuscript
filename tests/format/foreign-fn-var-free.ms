// conform: tags=diagnostics,parser,tier-core
// conform: phase=parse
// conform: origin=foreign-syntax diagnostics
fn var bump(var n: Int) Void {
    void
}
// expect-error: MS1000 4:4-4:7 'fn var' marks a method that changes its receiver, as in 'fn var Counter.add(n Int) Void { ... }'; a free function takes 'var' on the parameter instead: 'fn add(var counter Counter, n Int) Void { ... }'
// expect-format-exit: 1
