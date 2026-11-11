import (
	expect_equal, expect_false, expect_true from "@std/test/test.ms",

	Approved,
	Counter,
	Mode,
	approve,
	counter,
	entity,
	level,
	nonce_of,
	safe,
	wild from "./gate.ms",
)

fn show[T](value: T) String:
	return "{value}"

test "module functions and methods work on an opaque value":
	a := approve("u1")
	entity(a) | expect_equal("u1")?
	nonce_of(a) | expect_equal("n1")?
	a.label() | expect_equal("approved:u1")?

test "a mutating method changes an opaque value":
	var c = counter()
	c.bump()
	c.bump()
	c.value() | expect_equal(2)?

test "an opaque value copies, clones and compares":
	a := approve("u1")
	b := a.clone()
	expect_true(a == b)?
	expect_false(a == approve("u2"))?
	entity(b) | expect_equal("u1")?

test "an opaque value prints only its type name":
	a := approve("u1")
	"{a}" | expect_equal("Approved")?
	a.to_string() | expect_equal("Approved")?
	show(a) | expect_equal("Approved")?
	show([a, approve("u2")]) | expect_equal("[Approved, Approved]")?
	show(counter()) | expect_equal("Counter")?
	show(safe()) | expect_equal("Mode")?
	show(wild(7)) | expect_equal("Mode")?

test "an opaque value lives in collections and optionals":
	var all = List[Approved]()
	all.append(approve("u1"))
	all.append(approve("u2"))
	all.length() | expect_equal(2)?
	entity(all[1]) | expect_equal("u2")?

	maybe: Approved? := approve("u3")

	if found := maybe:
		entity(found) | expect_equal("u3")?
	else:
		expect_true(false)?

test "an opaque alternative is built and read through the module":
	level(safe()) | expect_equal(0)?
	level(wild(4)) | expect_equal(4)?
