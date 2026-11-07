import expect_equal from "@std/test/test.ms"
import panic from "@std/core.ms"

fn text(value: Int) String?: "dynamic optional payload {value}"

fn texts(value: Int) List[String]?: ["dynamic optional payload {value}"]

fn unexpected_text() String?: panic("present Optional must not call fallback")

fn unexpected_texts() List[String]?: panic("present Optional must not call fallback")

type Fallback:
    calls: Int

impl Fallback:
    var fn create() String?:
        self.calls += 1
        return "fallback {self.calls}"

test "or_else transfers an owned String Optional call":
    let kept = text(1).or_else(unexpected_text)
    try expect_equal(kept.get(), "dynamic optional payload 1")

test "or_else transfers a last-use String Optional":
    let present = text(2)
    let kept = present.or_else(unexpected_text)
    try expect_equal(kept.get(), "dynamic optional payload 2")

test "or_else copies a borrowed String Optional at its declared boundary":
    let present = text(3)
    let kept = present.or_else(unexpected_text)
    try expect_equal(present.get(), "dynamic optional payload 3")
    try expect_equal(kept.get(), "dynamic optional payload 3")

test "or_else transfers an owned List Optional":
    let kept = texts(4).or_else(unexpected_texts)
    try expect_equal(kept.get(), ["dynamic optional payload 4"])

test "or_else copies a borrowed List Optional at its declared boundary":
    let present = texts(5)
    let kept = present.or_else(unexpected_texts)
    try expect_equal(present.get(), ["dynamic optional payload 5"])
    try expect_equal(kept.get(), ["dynamic optional payload 5"])

test "or_else invokes a missing fallback once and skips a present fallback":
    var fallback = Fallback(0)
    let missing: String? = none
    let recovered = missing.or_else(fn: fallback.create())
    try expect_equal(recovered.get(), "fallback 1")

    let kept = text(6).or_else(fn: fallback.create())
    try expect_equal(kept.get(), "dynamic optional payload 6")
    try expect_equal(fallback.calls, 1)

test "or_else permits a fallback that stays absent":
    let missing: String? = none
    let kept = missing.or_else(fn: none)
    try expect_equal(kept, none)

test "bound or_else preserves its captured Optional across calls":
    let bound = text(7).or_else
    let first = bound(unexpected_text)
    let second = bound(unexpected_text)
    try expect_equal(first.get(), "dynamic optional payload 7")
    try expect_equal(second.get(), "dynamic optional payload 7")

fn text_callback(fail: Bool) (fn() String?)!:
    if fail: return error(Error("callback unavailable"))

    return ok(unexpected_text)

test "owned data receiver keeps its value across a later try":
    let kept = text(8).or_else(try text_callback(false))
    try expect_equal(kept.get(), "dynamic optional payload 8")

    let original = text(9)
    let moved = original.or_else(try text_callback(false))
    try expect_equal(moved.get(), "dynamic optional payload 9")

test "borrowed data receiver remains borrowed across a later try":
    let original = text(10)
    let kept = original.or_else(try text_callback(false))
    try expect_equal(original.get(), "dynamic optional payload 10")
    try expect_equal(kept.get(), "dynamic optional payload 10")
