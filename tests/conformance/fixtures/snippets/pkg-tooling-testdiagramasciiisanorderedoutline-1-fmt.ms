# conform: tags=formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/review_test.go:121 TestDiagramASCIIIsAnOrderedOutline
def one() -> Int:
    return 1

def two() -> Int:
    return one() + one()
