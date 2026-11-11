// A `let` that keeps a part of a borrowed result or of an indexed temporary copies just
// that part.
import expect_equal from "@std/test/test.ms"

fn failed() String!:
	return error(Error("boom"))

fn names(suite: String) List[String]:
	if suite == "kernels": return ["sieve", "nbody"]
	return ["call"]

test "a let keeps the message of a borrowed error":
	r := failed()
	message := r.err().message
	expect_equal(message.length(), 4)?

test "a let keeps an element of a returned list":
	first := names("kernels")[0]
	expect_equal(first, "sieve")?
