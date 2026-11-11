// conform: tags=faults,match,modules,mutation,optional,stdlib-testing,testing,tier-core,try-result
// conform: phase=test
// conform: origin=tests/e2e/testdata/accept/collection-call-order.ms
import expect_equal from "@std/test/test.ms"

test "receiver before index":
	values := [7]
	var calls = 0
	index: Int? := 0
	result := values.get(
		match index:
			i:
				calls += 1
				i
			none: 0
	)
	expect_equal(result, 7)?
	expect_equal(calls, 1)?
