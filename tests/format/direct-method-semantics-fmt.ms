// conform: tags=alternatives,control-flow,formatter,interfaces,lists,match,modules,parser,records,stdlib-errors,stdlib-testing,strings,testing,tier-stdlib,try-result
// conform: phase=parse
// conform: origin=tests/e2e/testdata/accept/direct-method-semantics.ms
import expect_true, fail from "@std/test/test.ms"

interface Shape {
	fn area() Int
	fn scaled(by Int) Int
	fn checked(limit Int) Int!Error
	fn grow(depth Int) Int
}

type Rect {
	w Int
	h Int
}

enum Sign {
	Plus(n Int)
	Minus(n Int)
}

fn Rect.area() Int {
	return self.w * self.h
}

fn Rect.scaled(by Int) Int {
	return self.area() * by
}

fn Rect.checked(limit Int) Int!Error {
	if self.area() > limit {
		return error(cause: Error("too big"))
	}
	return ok(value: self.area())
}

fn Rect.grow(depth Int) Int {
	if depth == 0 {
		return self.w
	}
	return self.grow(depth: depth - 1) + 1
}

fn Sign.area() Int {
	match self {
		Plus(n) => return n
		Minus(n) => return 0 - n
	}
}

fn Sign.scaled(by Int) Int {
	return self.area() * by
}

fn Sign.checked(limit Int) Int!Error {
	return ok(value: self.area())
}

fn Sign.grow(depth Int) Int {
	return depth
}

fn through(shape Shape) Int {
	return shape.scaled(by: 2)
}

fn tried(rect Rect, limit Int) Int!Error {
	first := rect.checked(limit: limit)?
	return ok(value: first + (rect.checked(limit: limit + 100)?))
}

fn order(rect Rect, var log List[String]) Int {
	log.append(value: "receiver")
	return rect.scaled(by: id(log: log))
}

fn id(var log List[String]) Int {
	log.append(value: "argument")
	return 1
}

test "direct methods" {
	rect := Rect(w: 3, h: 4)
	(rect.area() == 12) | expect_true?
	(rect.scaled(by: 3) == 36) | expect_true?
	(through(shape: rect) == 24) | expect_true?
	(through(shape: Plus(n: 5)) == 10) | expect_true?
	(Minus(n: 4).area() == 0 - 4) | expect_true?
	(rect.grow(depth: 10) == 13) | expect_true?

	match tried(rect: rect, limit: 12) {
		ok(value) => (value == 24) | expect_true?
		error(cause) => return fail(cause.message)
	}

	match tried(rect: rect, limit: 11) {
		ok(_value) => return fail("expected failure")
		error(cause) => (cause.message == "too big") | expect_true?
	}

	var log = List[String]()
	(order(rect: rect, log: log) == 12) | expect_true?
	(log.join(separator: ",") == "receiver,argument") | expect_true?
}
// expect-format: rewritten
// expect-formatted: import expect_true, fail from "@std/test/test.ms"
// expect-formatted:
// expect-formatted: interface Shape {
// expect-formatted: \tfn area() Int
// expect-formatted: \tfn scaled(by Int) Int
// expect-formatted: \tfn checked(limit Int) Int!
// expect-formatted: \tfn grow(depth Int) Int
// expect-formatted: }
// expect-formatted:
// expect-formatted: type Rect {
// expect-formatted: \tw, h Int
// expect-formatted: }
// expect-formatted:
// expect-formatted: enum Sign {
// expect-formatted: \tPlus(n Int)
// expect-formatted: \tMinus(n Int)
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn Rect.area() Int {
// expect-formatted: \treturn self.w * self.h
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn Rect.scaled(by Int) Int {
// expect-formatted: \treturn self.area() * by
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn Rect.checked(limit Int) Int! {
// expect-formatted: \tif self.area() > limit {
// expect-formatted: \t\treturn error(cause: Error("too big"))
// expect-formatted: \t}
// expect-formatted: \treturn ok(value: self.area())
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn Rect.grow(depth Int) Int {
// expect-formatted: \tif depth == 0 {
// expect-formatted: \t\treturn self.w
// expect-formatted: \t}
// expect-formatted: \treturn self.grow(depth: depth - 1) + 1
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn Sign.area() Int {
// expect-formatted: \tmatch self {
// expect-formatted: \t\tPlus(n) => return n
// expect-formatted: \t\tMinus(n) => return 0 - n
// expect-formatted: \t}
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn Sign.scaled(by Int) Int {
// expect-formatted: \treturn self.area() * by
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn Sign.checked(limit Int) Int! {
// expect-formatted: \treturn ok(value: self.area())
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn Sign.grow(depth Int) Int {
// expect-formatted: \treturn depth
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn through(shape Shape) Int {
// expect-formatted: \treturn shape.scaled(by: 2)
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn tried(rect Rect, limit Int) Int! {
// expect-formatted: \tfirst := rect.checked(limit: limit)?
// expect-formatted: \treturn ok(value: first + (rect.checked(limit: limit + 100)?))
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn order(rect Rect, var log List[String]) Int {
// expect-formatted: \tlog.append(value: "receiver")
// expect-formatted: \treturn rect.scaled(by: id(log: log))
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn id(var log List[String]) Int {
// expect-formatted: \tlog.append(value: "argument")
// expect-formatted: \treturn 1
// expect-formatted: }
// expect-formatted:
// expect-formatted: test "direct methods" {
// expect-formatted: \trect := Rect(w: 3, h: 4)
// expect-formatted: \t(rect.area() == 12) | expect_true?
// expect-formatted: \t(rect.scaled(by: 3) == 36) | expect_true?
// expect-formatted: \t(through(shape: rect) == 24) | expect_true?
// expect-formatted: \t(through(shape: Plus(n: 5)) == 10) | expect_true?
// expect-formatted: \t(Minus(n: 4).area() == 0 - 4) | expect_true?
// expect-formatted: \t(rect.grow(depth: 10) == 13) | expect_true?
// expect-formatted:
// expect-formatted: \tmatch tried(rect: rect, limit: 12) {
// expect-formatted: \t\tok(value) => (value == 24) | expect_true?
// expect-formatted: \t\terror(cause) => return fail(cause.message)
// expect-formatted: \t}
// expect-formatted:
// expect-formatted: \tmatch tried(rect: rect, limit: 11) {
// expect-formatted: \t\tok(_value) => return fail("expected failure")
// expect-formatted: \t\terror(cause) => (cause.message == "too big") | expect_true?
// expect-formatted: \t}
// expect-formatted:
// expect-formatted: \tvar log = List[String]()
// expect-formatted: \t(order(rect: rect, log: log) == 12) | expect_true?
// expect-formatted: \t(log.join(separator: ",") == "receiver,argument") | expect_true?
// expect-formatted: }
