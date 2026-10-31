# conform: tags=faults,formatter,optional,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/optional_test.go:14 TestOptionalArgumentsCompose
fn number(value: Int?) Int: return value.get()

fn call() Int: return
