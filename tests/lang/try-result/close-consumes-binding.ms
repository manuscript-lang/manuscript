// conform: tags=scope-cleanup,testing,try-result,records,tier-stdlib,stdlib-testing
// conform: phase=test
import expect_equal from "@std/test/test.ms"

type Log {
	lines List[String]
}

type Gate {
	name String
	log Log
}

fn move Gate.close() Void! {
	print(f"close {self.name}")
}

type Pair {
	first Gate
	second Gate
}

fn shut(move gate Gate) Void! {
	return gate.close()
}

fn once() Void! {
	gate := Gate("a", Log([]))
	gate.close()?
}

fn holder() Void! {
	pair := Pair(Gate("x", Log([])), Gate("y", Log([])))
	pair.first.close()?
}

fn through_parameter() Void! {
	shut(Gate("p", Log([])))?
}

test "an explicit close consumes the binding and scope end closes nothing more" {
	once()?
	through_parameter()?
	holder()?
	expect_equal(1, 1)?
}
// expect-exit: 0
// expect-tests: passed=1 failed=0
