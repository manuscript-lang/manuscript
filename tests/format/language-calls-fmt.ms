// conform: tags=control-flow,faults,formatter,modules,mutation,parser,stdlib-collections,stdlib-faults,tier-stdlib
// conform: phase=parse
// conform: origin=bench/perf/language/calls.ms
import panic from "@std/core.ms"

fn add(a Int, b Int) Int => a + b

export fn main() Int {
	var sum = 0
	for i in 0..5000000 {
		sum = add(sum, i)
	}
	if sum != 12499997500000 { return panic("calls checksum") }

	return 0
}
// expect-format: rewritten
// expect-formatted: import panic from "@std/core.ms"
// expect-formatted:
// expect-formatted: fn add(a, b Int) Int => a + b
// expect-formatted:
// expect-formatted: export fn main() Int {
// expect-formatted: \tvar sum = 0
// expect-formatted: \tfor i in 0..5000000 {
// expect-formatted: \t\tsum = add(sum, i)
// expect-formatted: \t}
// expect-formatted: \tif sum != 12499997500000 { return panic("calls checksum") }
// expect-formatted:
// expect-formatted: \treturn 0
// expect-formatted: }
