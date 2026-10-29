import {expect_true, expect_false, expect_equal} from "@std/test.ms"

type CustomerKey:
    id: Int
    label: String

impl Equal for CustomerKey:
    fn equals(other: CustomerKey) Bool:
        return self.id == other.id

impl Hashable for CustomerKey:
    fn hash() Int: self.id

type Version:
    major: Int

impl Comparable for Version:
    fn compare(other: Version) Int:
        return self.major - other.major

interface Merge:
    fn merge(other: Self) Int

impl Merge for Version:
    fn merge(other: Version) Int:
        return self.major + other.major

fn same[T: Equal](left: T, right: T) Bool:
    return left.equals(right)

fn lower[T: Comparable](left: T, right: T) Bool:
    return left.compare(right) < 0

fn total[T: Merge](left: T, right: T) Int:
    return left.merge(right)

test "implementations take their own type":
    let a = CustomerKey(1, "a")
    let b = CustomerKey(1, "b")
    try expect_true(a == b)
    try expect_true(a.equals(b))
    try expect_true(Version(1).compare(Version(2)) < 0)

test "bounds take two values of the bounded type":
    try expect_true(same(CustomerKey(1, "a"), CustomerKey(1, "b")))
    try expect_false(same(CustomerKey(1, "a"), CustomerKey(2, "a")))
    try expect_true(lower(Version(1), Version(2)))
    try expect_true(lower(1, 2))
    try expect_equal(total(Version(2), Version(3)), 5)

test "interface values of different types are unequal":
    let a: Equal = CustomerKey(1, "a")
    let b: Equal = CustomerKey(1, "z")
    try expect_true(a.equals(b))
    try expect_false(a.equals(1))

    let order: Comparable = Version(1)
    try expect_true(order.compare(Version(3)) < 0)

test "keys use the custom equality":
    let keys = {CustomerKey(1, "a"): "first"}
    try expect_equal(keys.get(CustomerKey(1, "b")).get(), "first")
