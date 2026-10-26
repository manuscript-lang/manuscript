from "@std/math.ms" import floor
from "@std/testing.ms" import expect_equal

def original(value: Int = 7) -> Int: value + 1

def replacement(value: Int) -> Int: value + 2

def original_float(value: Float = 7.0) -> Float: value

def choose[T](left: T, right: T) -> T: right

type Offset:
    base: Int

impl Offset:
    def original(value: Int = 7) -> Int: self.base + value

    def replacement(value: Int) -> Int: self.base + value + 1

test "required source functions replace defaulted callable values":
    var callback = original
    callback = replacement
    try expect_equal(callback(3), 5)

    let copied = callback
    try expect_equal(copied(4), 6)
    try expect_equal(choose(original, replacement)(3), 5)
    try expect_equal(choose(replacement, original)(3), 4)

    let callbacks = [original, replacement]
    try expect_equal(callbacks[0](3), 4)
    try expect_equal(callbacks[1](3), 5)

test "required lambdas replace defaulted callable values":
    var callback = original
    callback = lambda (value: Int): value + 2
    try expect_equal(callback(3), 5)

test "required native functions replace defaulted callable values":
    var callback = original_float
    callback = floor
    try expect_equal(callback(3.5), 3.0)

test "required bound methods replace defaulted callable values":
    let offset = Offset(2)
    var callback = offset.original
    callback = offset.replacement
    try expect_equal(callback(3), 6)

def original_text(value: String = "default") -> Int: value.length()

def original_predicate(value: String = "default") -> Bool: False

test "required lambda adapters retain supplied owned payloads":
    var callback = original_text
    callback = lambda (value: String): value.length()

    let text = "a sufficiently long string payload".clone()
    try expect_equal(callback(text), 34)

test "required bound native methods decode supplied payloads":
    var callback = original_predicate
    callback = "the borrowed needle haystack".contains
    try expect_equal(callback("needle".clone()), True)

interface Reader:
    def read(value: Optional[Int] = none) -> Int

type ReaderOffset:
    base: Int

impl Reader for ReaderOffset:
    def read(value: Optional[Int]) -> Int: self.base + value.get(5)

test "inherited defaults remain available on immutable bound callables":
    let offset = ReaderOffset(2)
    let callback = offset.read
    try expect_equal(callback(), 7)
    try expect_equal(callback(3), 5)

test "inferred callable returns use required arguments consistently":
    let factory = lambda (flag: Bool):
        if flag:
            return original

        return replacement

    try expect_equal(factory(True)(3), 4)
    try expect_equal(factory(False)(3), 5)

    let callback = match True:
        case True: original
        case False: replacement

    try expect_equal(callback(3), 4)

    let callbacks = {"original": original, "replacement": replacement}
    try expect_equal(callbacks["original"](3), 4)
    try expect_equal(callbacks["replacement"](3), 5)
