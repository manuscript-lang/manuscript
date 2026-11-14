// conform: tags=testing,tier-io
// conform: phase=test
import (
	Placement, PromiseOptions, promise from "@std/concurrency/promise.ms",
	expect_equal from "@std/test/test.ms",
)
import stringify from "@std/data/json.ms"

// Helpers the compiler writes for a type that contains itself (JSON encoders, equality,
// formatting, copies) recurse once per level, like any recursive function. A promise task
// starts on a 512 KiB stack, so each must grow it the way a written function does.
type Link:
	next: Link?
	value: Int

fn chain(n: Int) Link:
	var head = Link(none, 0)
	for i in 1..n:
		head = Link(head, i)
	return head

fn stringify_chain() Int!:
	head := chain(300000)
	return ok(if stringify(head).is_ok(): 1 else: 0)

fn clone_chain() Int!:
	head := chain(100000)
	copy := head.clone()
	return ok(if copy == head: copy.value else: -1)

fn on_a_task(f: fn() Int!) Int:
	p := promise(fn: f(), options: PromiseOptions(placement: Placement.Spread))
	return p.wait().get(-2)

test "a JSON encoder recurses past a promise task's first stack slot":
	expect_equal(on_a_task(stringify_chain), 0)?

test "copying and comparing a deep chain in a promise":
	expect_equal(on_a_task(clone_chain), 100000 - 1)?
