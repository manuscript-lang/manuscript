# conform: tags=formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/diff_test.go:36 TestParseDiffAndReverseApply
def one() -> Int:
    let x = 1
    return x

def two() -> Int:
    return 2
