# conform: tags=parser,tier-core
# conform: phase=parse
# conform: origin=pkg/lower/int_bounds_test.go:397 TestNonnegativeRemainderBoundsOracle
fn probe(value: Int) Int: return value %% %d
