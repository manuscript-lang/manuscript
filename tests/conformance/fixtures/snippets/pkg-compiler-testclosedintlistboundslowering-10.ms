# conform: tags=diagnostics,optional,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/list_bounds_test.go:33 TestClosedIntListBoundsLowering
def probe(flag: Bool, fallback: Optional[Int]) -> Int: ...
