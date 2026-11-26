// conform: tags=diagnostics,parser,tier-core
// conform: phase=parse
// conform: origin=foreign-syntax diagnostics
fn f() Void {
    await work()
}
// expect-error: MS1000 5:5-5:10 'await' is not a keyword; call the function directly, or start concurrent work with promise(fn: ...) from "@std/concurrency/promise.ms"
// expect-format-exit: 1
