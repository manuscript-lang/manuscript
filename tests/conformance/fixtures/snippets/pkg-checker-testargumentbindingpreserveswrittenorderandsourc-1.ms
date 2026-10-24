# conform: tags=diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/checker/positional_arguments_test.go:26 TestArgumentBindingPreservesWrittenOrderAndSource
def f(first: Int = 1, second: Int = 2, third: Int = 3) -> Int: first

def run(first: Int, second: Int, third: Int) -> Int: ...
