// conform: tags=diagnostics,faults,formatter,optional,tier-core
// conform: phase=check,parse
// conform: origin=pkg/checker/optional_test.go:12 TestOptionalArgumentPreservesSourceTypeAndAST
import panic from "@std/core.ms"

fn f(value Int?) Int => return value or panic("called Optional.get() on null")

fn call() Int => return f(4)
// expect-exit: 0
