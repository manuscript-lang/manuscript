// conform: tags=faults,formatter,optional,parser,tier-core
// conform: phase=parse
// conform: origin=pkg/checker/optional_test.go:12 TestOptionalArgumentPreservesSourceTypeAndAST
import panic from "@std/core.ms"

fn f(value: Int?) Int: return value or panic("called Optional.get() on null")

fn call() Int: return f(4)
