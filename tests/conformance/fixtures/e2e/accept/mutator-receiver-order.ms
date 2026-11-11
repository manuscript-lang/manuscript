// conform: tags=testing,tier-stdlib
// conform: phase=test
import expect_equal from "@std/test/test.ms"

fn receiver(var events: List[Int]) List[Int]:
	events.append(1)
	return [0]

fn argument(var events: List[Int]) Int:
	events.append(2)
	return 9

fn checked(var events: List[Int], fail: Bool) Int!:
	events.append(2)
	if fail: return error(Error("stop", kind: "EINVAL"))

	return ok(9)

fn set_with_try(var events: List[Int], fail: Bool) Unit!:
	receiver(var events).set(0, checked(var events, fail)?)
	events.append(3)

test "a changing method evaluates a temporary receiver before its arguments":
	var events: List[Int] = []
	receiver(var events).set(0, argument(var events))
	expect_equal(events, [1, 2])?

test "an argument that leaves through try follows the receiver and releases it":
	var events: List[Int] = []
	expect_equal(set_with_try(var events, false).is_ok(), true)?
	expect_equal(events, [1, 2, 3])?

	var failed: List[Int] = []
	expect_equal(set_with_try(var failed, true).is_error(), true)?
	expect_equal(failed, [1, 2])?
