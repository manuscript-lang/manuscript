// conform: tags=diagnostics,parser,tier-core
// conform: phase=parse
// conform: origin=foreign-syntax diagnostics
fn f() Void {
    async work()
}
// expect-error: MS1000 5:5-5:10 'async' is not a keyword; call the function directly, or start concurrent work with promise(fn: ...) from "@std/concurrency/promise.ms"
// expect-format-exit: 1
