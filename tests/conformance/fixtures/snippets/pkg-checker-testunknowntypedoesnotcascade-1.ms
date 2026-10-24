# conform: tags=diagnostics,match,optional,tier-core
# conform: phase=check
# conform: origin=pkg/checker/defaults_test.go:89 TestUnknownTypeDoesNotCascade
def peek() -> Missing:
    return 0

def f() -> Int:
    match peek():
        case some(x):
            return x
        case none:
            return 0
