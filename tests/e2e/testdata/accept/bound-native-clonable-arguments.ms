import (
	append_file, read_file, temporary from "@std/os/fs.ms",
	expect_contains, expect_equal, expect_fault from "@std/test/test.ms",
)

test "bound list mutators copy named string inputs without consuming callers":
	var values = ["old"]
	next := "new-{1}"
	set := values.set
	set(value: next, index: 0)
	expect_equal(next, "new-1")?

	append := values.append
	append(next)

	insert := values.insert
	insert(value: next, index: 1)

	replace := values.replace
	old := replace(0, next)
	expect_equal(old, "new-1")?
	expect_equal(next, "new-1")?
	expect_equal(values, ["new-1", "new-1", "new-1"])?

fn fill[T: Clonable](var target: List[T], item: T) Unit:
	append := target.append
	append(item)
	append(item)

test "generic bound mutator copies aggregate payload storage independently":
	var target: List[List[String]] = []
	var item = ["original-{1}"]
	fill(var target, item)
	item[0] = "changed"
	expect_equal(target, [["original-1"], ["original-1"]])?
	target[0][0] = "first"
	expect_equal(target[1][0], "original-1")?
	expect_equal(item[0], "changed")?

test "optional native adapter handles supplied and absent payloads":
	var values: List[String?] = ["first"]
	set := values.set
	text: String? := "next-{2}"
	set(0, text)
	set(0, none)
	set(0, text)
	expect_equal(values[0], text)?
	expect_equal(text.get(), "next-2")?

fn invalid(value: String, index: Int) Unit:
	var values = ["old"]
	set := values.set
	set(index, value)

test "invalid bound mutation does not consume the caller payload":
	text := "survives-{3}"
	fault := expect_fault(fn: invalid(text, 2))?
	expect_contains(fault, "index")?
	expect_equal(text, "survives-3")?

fn supplied(log: String) String!:
	append_file(log, "value,").wait()?
	return ok("supplied")

fn picked(log: String, fail: Bool) Int!:
	append_file(log, "index,").wait()?
	if fail: return error(Error("index failure"))

	return ok(0)

fn ordered(log: String, fail: Bool) List[String]!:
	var values = ["old"]
	set := values.set
	set(value: supplied(log)?, index: picked(log, fail)?)
	return ok(values)

test "bound native argument copies preserve named effects and propagation":
	tmp := temporary("bound-native-order-")?
	log := "{tmp.path()}/log"
	expect_equal((ordered(log, false)?), ["supplied"])?
	expect_equal((read_file(log).wait()?).decode_utf8().get(), "value,index,")?
	expect_equal(ordered(log, true).is_error(), true)?
	expect_equal(
		(read_file(log).wait()?).decode_utf8().get(), "value,index,value,index,"
	)?

test "nonconsuming bound methods continue borrowing ordinary inputs":
	values := ["a", "b"]
	contains := values.contains
	query := "b-{1}".slice(0, 1)?
	expect_equal(contains(query), true)?
	expect_equal(query, "b")?

test "bound native getter defaults remain unchanged":
	values := ["first"]
	get := values.get
	expect_equal(get(0), "first")?

	fallback := "fallback-{1}"
	expect_equal(get(2, fallback), fallback)?
	expect_equal(fallback, "fallback-1")?
