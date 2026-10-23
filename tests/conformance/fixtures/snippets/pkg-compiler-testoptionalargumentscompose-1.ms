# conform: tags=diagnostics,faults,optional,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/optional_test.go:14 TestOptionalArgumentsCompose
fn number(value: Optional[Int]) Int: return value.get()

fn call() Int: return
