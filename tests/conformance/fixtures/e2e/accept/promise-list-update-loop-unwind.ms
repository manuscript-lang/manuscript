// conform: tags=testing,tier-stdlib
// conform: phase=test
import (
	promise from "@std/concurrency/promise.ms",
	expect_equal from "@std/test/test.ms",
)

fn histogram(seed Int) Int!:
	var hist List[Int] = []
	for b in 0..16: hist.append(0)
	var x = seed
	for i in 0..1000:
		x = (x * 48271) % 2147483647
		hist[x % 16] = hist[x % 16] + 1
	var total = 0
	for b in 0..16: total += hist[b] * (b + 1)
	return ok(total)

fn overflows_late(width Int) Int!:
	var hist List[Int] = []
	for b in 0..8: hist.append(0)
	for i in 0..100:
		hist[i % width] = hist[i % width] + 1
	return ok(hist[0])

test "a task that updates a list in a loop gives the same answer as a direct call":
	for seed in [1, 7, 99]:
		direct := histogram(seed).get_or(-1)
		p := promise(() => histogram(seed))
		expect_equal(p.wait().get_or(-2), direct)?

test "a task that faults in the loop frees the list once":
	for width in [8, 20, 8, 20]:
		p := promise(() => overflows_late(width))
		expect_equal(p.wait().is_ok(), width == 8)?
