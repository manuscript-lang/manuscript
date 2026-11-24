// conform: tags=diagnostics,faults,optional,tier-core
// conform: phase=check
// conform: origin=pkg/compiler/optional_test.go:14 TestOptionalArgumentsCompose
import panic from "@std/core.ms"

fn number(value Int?) Int => return value or panic("called Optional.get() on null")

fn call() Int => return
