# conform: tags=formatter,optional,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/list_bounds_test.go:33 TestClosedIntListBoundsLowering
def probe(flag: Bool, fallback: Optional[Int]) -> Int: ...
