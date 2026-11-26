// conform: tags=alternatives,match,control-flow,tier-core,testing
// conform: phase=test
import expect_equal from "@std/test/test.ms"

enum State {
	Name(text String)
	Done
}

// The payload `text` is last read inside the value assigned to `state`; the old value
// is only released once that value is built, so the assignment does not conflict with
// the borrow.
fn step(move start String) String {
	var state = State.Name(start)

	match state {
		Name(text) => {
			state = State.Name(text + "!")
		}
		Done => {
			print("done")
		}
	}

	match state {
		Name(text) => {
			return text.clone()
		}
		Done => {
			return ""
		}
	}
}

test "a match arm rebuilds the matched variable from its payload" {
	expect_equal(step("a"), "a!")?
}
// expect-exit: 0
// expect-tests: passed=1 failed=0
