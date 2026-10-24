# conform: tags=diagnostics,faults,optional,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/optional_test.go:14 TestOptionalArgumentsCompose
def number(value: Optional[Int]) -> Int: return value.get()

def call() -> Int: return
