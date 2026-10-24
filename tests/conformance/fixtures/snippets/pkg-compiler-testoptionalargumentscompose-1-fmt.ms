# conform: tags=faults,formatter,optional,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/optional_test.go:14 TestOptionalArgumentsCompose
def number(value: Optional[Int]) -> Int: return value.get()

def call() -> Int: return
