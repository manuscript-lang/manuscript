// conform: tags=testing,tier-stdlib
// conform: phase=test
import expect_equal, expect_false, expect_true from "@std/test/test.ms"

type CustomerKey:
	id: Int
	label: String

fn CustomerKey.equals(other: CustomerKey) Bool:
	return self.id == other.id

fn CustomerKey.hash() Int: self.id

type Version:
	major: Int

fn Version.compare(other: Version) Int:
	return self.major - other.major

interface Merge:
	fn merge(other: Self) Int

fn Version.merge(other: Version) Int:
	return self.major + other.major

fn same[T: Equal](left: T, right: T) Bool:
	return left.equals(right)

fn lower[T: Comparable](left: T, right: T) Bool:
	return left.compare(right) < 0

fn total[T: Merge](left: T, right: T) Int:
	return left.merge(right)

test "implementations take their own type":
	a := CustomerKey(1, "a")
	b := CustomerKey(1, "b")
	expect_true(a == b)?
	expect_true(a.equals(b))?
	expect_true(Version(1).compare(Version(2)) < 0)?

test "bounds take two values of the bounded type":
	expect_true(same(CustomerKey(1, "a"), CustomerKey(1, "b")))?
	expect_false(same(CustomerKey(1, "a"), CustomerKey(2, "a")))?
	expect_true(lower(Version(1), Version(2)))?
	expect_true(lower(1, 2))?
	expect_equal(total(Version(2), Version(3)), 5)?

test "interface values of different types are unequal":
	a: Equal := CustomerKey(1, "a")
	b: Equal := CustomerKey(1, "z")
	expect_true(a.equals(b))?
	expect_false(a.equals(1))?

	order: Comparable := Version(1)
	expect_true(order.compare(Version(3)) < 0)?

test "keys use the custom equality":
	keys := {CustomerKey(1, "a"): "first"}
	expect_equal(keys.get(CustomerKey(1, "b")).get(), "first")?
