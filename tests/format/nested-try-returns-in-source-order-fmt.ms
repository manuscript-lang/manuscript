// conform: tags=control-flow,faults,formatter,interpolation,lists,modules,mutation,parser,stdlib-errors,stdlib-testing,strings,testing,tier-stdlib,try-result
// conform: phase=parse
// conform: origin=tests/e2e/testdata/accept/nested-try-returns-in-source-order.ms
import expect_true from "@std/test/test.ms"

fn step(var log List[String], move name String, n Int) Int!Error {
	log.append(value: name.clone())
	if n < 0 {
		return error(cause: Error(name))
	}

	return ok(value: n)
}

fn add(x Int, y Int) Int {
	return x + y
}

fn sum(var log List[String], a Int, b Int) Int!Error {
	v := ((step(log: log, name: "a", n: a)?) + (step(log: log, name: "b", n: b)?))
	log.append(value: "done")
	return ok(value: v)
}

fn arguments(var log List[String], a Int, b Int) Int!Error {
	return ok(
		value: add(
			x: step(log: log, name: "x", n: a)?,
			y: step(log: log, name: "y", n: b)?,
		)
	)
}

fn effect_first(var log List[String], a Int) Int!Error {
	log.append(value: "before")

	v := add(x: 1, y: step(log: log, name: "s", n: a)?)
	return ok(value: v)
}

fn loop(var log List[String], n Int) Int!Error {
	var total = 0
	var i = 0

	while i < n {
		total += step(log: log, name: "l", n: 1 - i)?
		i += 1
	}

	return ok(value: total)
}

fn joined(var log List[String]) String!Error {
	return ok(
		value: f"{step(log: log, name: "p", n: 1)?}-{step(log: log, name: "q", n: -1)?}"
	)
}

fn text(log List[String]) String {
	return log.join(separator: ",")
}

test "nested try" {
	var first = List[String]()
	expect_true((sum(log: first, a: 1, b: 2).get() == 3))?
	expect_true((text(log: first) == "a,b,done"))?

	var second = List[String]()
	expect_true((sum(log: second, a: -1, b: 2).err().message == "a"))?
	expect_true((text(log: second) == "a"))?

	var third = List[String]()
	expect_true((arguments(log: third, a: 1, b: -1).err().message == "y"))?
	expect_true((text(log: third) == "x,y"))?

	var fourth = List[String]()
	expect_true((effect_first(log: fourth, a: -1).err().message == "s"))?
	expect_true((text(log: fourth) == "before,s"))?

	var fifth = List[String]()
	expect_true((loop(log: fifth, n: 5).err().message == "l"))?
	expect_true((text(log: fifth) == "l,l,l"))?

	var sixth = List[String]()
	expect_true((joined(log: sixth).err().message == "q"))?
	expect_true((text(log: sixth) == "p,q"))?
}
// expect-format: rewritten
// expect-formatted: import expect_true from "@std/test/test.ms"
// expect-formatted:
// expect-formatted: fn step(var log List[String], move name String, n Int) Int! {
// expect-formatted: \tlog.append(value: name.clone())
// expect-formatted: \tif n < 0 {
// expect-formatted: \t\treturn error(cause: Error(name))
// expect-formatted: \t}
// expect-formatted:
// expect-formatted: \treturn ok(value: n)
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn add(x, y Int) Int {
// expect-formatted: \treturn x + y
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn sum(var log List[String], a, b Int) Int! {
// expect-formatted: \tv := ((step(log: log, name: "a", n: a)?) + (step(log: log, name: "b", n: b)?))
// expect-formatted: \tlog.append(value: "done")
// expect-formatted: \treturn ok(value: v)
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn arguments(var log List[String], a, b Int) Int! {
// expect-formatted: \treturn ok(
// expect-formatted: \t\tvalue: add(
// expect-formatted: \t\t\tx: step(log: log, name: "x", n: a)?,
// expect-formatted: \t\t\ty: step(log: log, name: "y", n: b)?,
// expect-formatted: \t\t)
// expect-formatted: \t)
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn effect_first(var log List[String], a Int) Int! {
// expect-formatted: \tlog.append(value: "before")
// expect-formatted:
// expect-formatted: \tv := add(x: 1, y: step(log: log, name: "s", n: a)?)
// expect-formatted: \treturn ok(value: v)
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn loop(var log List[String], n Int) Int! {
// expect-formatted: \tvar total = 0
// expect-formatted: \tvar i = 0
// expect-formatted:
// expect-formatted: \twhile i < n {
// expect-formatted: \t\ttotal += step(log: log, name: "l", n: 1 - i)?
// expect-formatted: \t\ti += 1
// expect-formatted: \t}
// expect-formatted:
// expect-formatted: \treturn ok(value: total)
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn joined(var log List[String]) String! {
// expect-formatted: \treturn ok(
// expect-formatted: \t\tvalue: f"{step(log: log, name: "p", n: 1)?}-{step(log: log, name: "q", n: -1)?}"
// expect-formatted: \t)
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn text(log List[String]) String {
// expect-formatted: \treturn log.join(separator: ",")
// expect-formatted: }
// expect-formatted:
// expect-formatted: test "nested try" {
// expect-formatted: \tvar first = List[String]()
// expect-formatted: \texpect_true((sum(log: first, a: 1, b: 2).get() == 3))?
// expect-formatted: \texpect_true((text(log: first) == "a,b,done"))?
// expect-formatted:
// expect-formatted: \tvar second = List[String]()
// expect-formatted: \texpect_true((sum(log: second, a: -1, b: 2).err().message == "a"))?
// expect-formatted: \texpect_true((text(log: second) == "a"))?
// expect-formatted:
// expect-formatted: \tvar third = List[String]()
// expect-formatted: \texpect_true((arguments(log: third, a: 1, b: -1).err().message == "y"))?
// expect-formatted: \texpect_true((text(log: third) == "x,y"))?
// expect-formatted:
// expect-formatted: \tvar fourth = List[String]()
// expect-formatted: \texpect_true((effect_first(log: fourth, a: -1).err().message == "s"))?
// expect-formatted: \texpect_true((text(log: fourth) == "before,s"))?
// expect-formatted:
// expect-formatted: \tvar fifth = List[String]()
// expect-formatted: \texpect_true((loop(log: fifth, n: 5).err().message == "l"))?
// expect-formatted: \texpect_true((text(log: fifth) == "l,l,l"))?
// expect-formatted:
// expect-formatted: \tvar sixth = List[String]()
// expect-formatted: \texpect_true((joined(log: sixth).err().message == "q"))?
// expect-formatted: \texpect_true((text(log: sixth) == "p,q"))?
// expect-formatted: }
