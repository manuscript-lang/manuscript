// conform: tags=diagnostics,parser,stdlib-tasks,tier-core
// conform: phase=parse
// conform: origin=foreign-syntax diagnostics
fn f() Void {
    go work()
}
// expect-error: MS1000 5:5-5:7 'go' is not a keyword; start concurrent work with promise(fn: ...) from "@std/concurrency/promise.ms": result := promise(fn: work()), then result.wait()
// expect-format-exit: 1
