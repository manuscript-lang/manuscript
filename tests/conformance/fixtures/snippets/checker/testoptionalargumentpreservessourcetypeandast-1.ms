// conform: tags=diagnostics,faults,optional,tier-core
// conform: phase=check
// conform: origin=pkg/checker/optional_test.go:12 TestOptionalArgumentPreservesSourceTypeAndAST
import panic from "@std/core.ms"

fn f(value Int?) Int: return value or panic("called Optional.get() on null")

fn call() Int: return f(4)
