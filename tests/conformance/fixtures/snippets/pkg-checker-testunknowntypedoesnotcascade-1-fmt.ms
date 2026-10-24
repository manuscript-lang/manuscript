# conform: tags=formatter,match,optional,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/defaults_test.go:89 TestUnknownTypeDoesNotCascade
def peek() -> Missing:
    return 0

def f() -> Int:
    match peek():
        case some(x):
            return x
        case none:
            return 0
