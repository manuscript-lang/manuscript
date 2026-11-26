// conform: tags=control-flow,formatter,match,modules,mutation,optional,stdlib-testing,testing,tier-core,try-result
// conform: phase=test,parse
// conform: origin=tests/e2e/testdata/accept/operand-order.ms
import expect_equal from "@std/test/test.ms"

export fn main() Int {
	var number = 1
	total := (
		number
		+ (
			match present(1) {
				value => {
					number += 1
					value
				} null => 0
			}
		)
	)
	if total != 2 {
		return 1
	}

	return 0
}

test "operands retain evaluation order" {
	main() | expect_equal(0)?
}

fn present[T](hold value T) &T? {
	return value
}
// expect-exit: 0
// expect-tests: passed=1 failed=0
