# conform: tags=formatter,parser,tier-core
# conform: phase=parse
# conform: origin=tests/e2e/call_depth_test.go:13 TestRunawayRecursionIsAFault
def depth(n: Int) -> Int:
    return 1 + depth(n + 1)

export def main() -> Int:
    return depth(0)
