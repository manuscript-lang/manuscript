# conform: tags=modules,parser,stdlib-string,strings,tier-stdlib
# conform: phase=parse
# conform: origin=pkg/lower/int_bounds_test.go:293 BenchmarkBuilderRangeScaling
import StringBuilder from "@std/string.ms"
fn probe() Int:
    let values = [
