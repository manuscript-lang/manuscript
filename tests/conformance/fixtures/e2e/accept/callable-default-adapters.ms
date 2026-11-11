// conform: tags=testing,tier-stdlib
// conform: phase=test
import (
	floor from "@std/math/math.ms",
	expect_equal from "@std/test/test.ms",
)

fn original(value: Int = 7) Int: value + 1

fn replacement(value: Int) Int: value + 2

fn original_float(value: Float = 7.0) Float: value

fn choose[T](left: T, right: T) T: right

type Offset:
	base: Int

fn Offset.original(value: Int = 7) Int: self.base + value

fn Offset.replacement(value: Int) Int: self.base + value + 1

test "required source functions replace defaulted callable values":
	var callback = original
	callback = replacement
	expect_equal(callback(3), 5)?

	copied := callback
	expect_equal(copied(4), 6)?
	expect_equal(choose(original, replacement)(3), 5)?
	expect_equal(choose(replacement, original)(3), 4)?

	callbacks := [original, replacement]
	expect_equal(callbacks[0](3), 4)?
	expect_equal(callbacks[1](3), 5)?

test "required lambdas replace defaulted callable values":
	var callback = original
	callback = fn(value: Int): value + 2
	expect_equal(callback(3), 5)?

test "required native functions replace defaulted callable values":
	var callback = original_float
	callback = floor
	expect_equal(callback(3.5), 3.0)?

test "required bound methods replace defaulted callable values":
	offset := Offset(2)
	var callback = offset.original

	// Assigning a method value takes its receiver, as assigning a closure takes its
	// captures.
	callback = offset.clone().replacement
	expect_equal(callback(3), 6)?

fn original_text(value: String = "default") Int: value.length()

fn original_predicate(value: String = "default") Bool: false

test "required lambda adapters retain supplied owned payloads":
	var callback = original_text
	callback = fn(value: String): value.length()

	text := "a sufficiently long string payload".clone()
	expect_equal(callback(text), 34)?

test "required bound native methods decode supplied payloads":
	var callback = original_predicate
	callback = "the borrowed needle haystack".contains
	expect_equal(callback("needle".clone()), true)?

interface Reader:
	fn read(value: Int?) Int

type ReaderOffset:
	base: Int

impl Reader for ReaderOffset:
	fn read(value: Int?) Int: self.base + value.get(5)

test "inherited defaults remain available on immutable bound callables":
	offset := ReaderOffset(2)
	callback := offset.read
	expect_equal(callback(), 7)?
	expect_equal(callback(3), 5)?

test "inferred callable returns use required arguments consistently":
	factory := fn(flag: Bool):
		if flag: return original
		return replacement

	expect_equal(factory(true)(3), 4)?
	expect_equal(factory(false)(3), 5)?

	callback := match true:
		true: original
		false: replacement

	expect_equal(callback(3), 4)?

	callbacks := {"original": original, "replacement": replacement}
	expect_equal(callbacks["original"](3), 4)?
	expect_equal(callbacks["replacement"](3), 5)?
