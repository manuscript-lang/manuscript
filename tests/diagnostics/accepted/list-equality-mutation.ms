// conform: tags=aliasing,closures,control-flow,interfaces,interpolation,lists,match,modules,mutation,records,stdlib-collections,stdlib-testing,strings,testing,tier-stdlib,try-result
// conform: phase=check
// The one-owner model rejects a closure that mutates a list while `==` compares it: the
// closure takes `left`, `right` and `side` with it, `target` only borrows, and a
// function value cannot be cloned. This used to be a runtime test of retained headers.
// conform: origin=tests/e2e/testdata/accept/list-equality-mutation.ms
import fail from "@std/test/test.ms"

type Element {
	id Int
	on_equal fn() Void
}

fn Element.equals(other Element) Bool {
	self.on_equal()
	return self.id == other.id
}

type Visits {
	count Int
}

fn noop() Void {
	return
}

fn check_equality(side String, mutation String) Void! {
	var left List[Element] = []
	var right List[Element] = []
	calls := Visits(0)

	visit := () => {
		calls.count += 1
		if calls.count != 1 {
			return
		}

		target := if side == "right" { right } else { left }
		next_action := target[1].on_equal

		if mutation == "shrink" or mutation == "shrink_mismatch" {
			target.splice(0, target.length(), [])
			return
		}

		if mutation == "append" {
			target.append(Element(7, noop))
			return
		}

		if mutation == "append_write" {
			target.append(Element(7, noop))
			target.set(1, Element(77, next_action))
			return
		}

		if mutation == "grow_write" {
			for index in 0..100 {
				target.append(Element(7, noop))
			}
			target.set(1, Element(77, next_action))
			return
		}

		target.set(1, Element(77, next_action))
	}

	for id in [1, 2, 3] {
		left.append(Element(id, visit))
		right.append(Element(id, visit))
	}

	if mutation == "shrink_mismatch" {
		right.set(2, Element(99, visit))
	}

	expected := (
		mutation != "shrink_mismatch"
		and mutation != "append_write"
		and mutation != "overwrite"
	)
	expected_calls := if mutation == "append_write" or mutation == "overwrite" { 2 } else { 3 }
	same := left == right
	if same != expected or calls.count != expected_calls {
		return fail(
			f"{side}/{mutation}: equality {same}/{calls.count}, expected {expected}/{expected_calls}"
		)
	}
}

test "element Equal mutating either List retains both captured headers" {
	for side in ["left", "right"] {
		for mutation in [
			"shrink", "shrink_mismatch", "append", "append_write", "grow_write",
			"overwrite"
		] {
			(check_equality(side, mutation)?)
		}
	}
}
// expect-error: MS3060 33:15 cannot change `calls.count`: `calls` is an immutable binding, immutable including its contents; declare it `var calls` to change it
// expect-fix: 30:5-30:13 "var calls ="
// expect-error: MS3060 42:13 cannot change `target`: `target` is an immutable binding, immutable including its contents; declare it `var target` to change it
// expect-fix: 38:9-38:18 "var target ="
// expect-error: MS3060 47:13 cannot change `target`: `target` is an immutable binding, immutable including its contents; declare it `var target` to change it
// expect-fix: 38:9-38:18 "var target ="
// expect-error: MS3060 52:13 cannot change `target`: `target` is an immutable binding, immutable including its contents; declare it `var target` to change it
// expect-fix: 38:9-38:18 "var target ="
// expect-error: MS3060 53:13 cannot change `target`: `target` is an immutable binding, immutable including its contents; declare it `var target` to change it
// expect-fix: 38:9-38:18 "var target ="
// expect-error: MS3060 59:17 cannot change `target`: `target` is an immutable binding, immutable including its contents; declare it `var target` to change it
// expect-fix: 38:9-38:18 "var target ="
// expect-error: MS3060 61:13 cannot change `target`: `target` is an immutable binding, immutable including its contents; declare it `var target` to change it
// expect-fix: 38:9-38:18 "var target ="
// expect-error: MS3060 65:9 cannot change `target`: `target` is an immutable binding, immutable including its contents; declare it `var target` to change it
// expect-fix: 38:9-38:18 "var target ="
// expect-error: MS3000 32:14 this closure outlives the statement, so it takes `side` with it, but `side` is used again at 86:16; capture `side.clone()` to keep the original
// expect-error: MS3000 32:14 this closure outlives the statement, so it takes `mutation` with it, but `mutation` is used again at 73:8; capture `mutation.clone()` to keep the original
// expect-error: MS3000 32:14 this closure outlives the statement, so it takes `left` with it, but `left` is used again at 69:9; capture `left.clone()` to keep the original
// expect-error: MS3000 32:14 this closure outlives the statement, so it takes `right` with it, but `right` is used again at 70:9; capture `right.clone()` to keep the original
// expect-error: MS3030 32:14 this closure changes captured `calls`, so it cannot be returned, stored or passed to a moving parameter; keep the closure local, or have it return a new value instead of changing `calls`
// expect-error: MS3000 32:14 this closure outlives the statement, so it takes `calls` with it, but `calls` is used again at 84:28; capture `calls.clone()` to keep the original
// expect-error: MS3000 38:40 `right` is moved here but used again at 32:14; a value has one owner, so move it only at its last use, or pass `right.clone()` if the original is still needed
// expect-error: MS3000 38:55 `left` is moved here but used again at 32:14; a value has one owner, so move it only at its last use, or pass `left.clone()` if the original is still needed
