import (
    expect_equal from "@std/test/test.ms",
    ReadStream, Transform, WriteStream, through from "@std/io/io.ms",
    from_list, collect from "@std/io/streams.ms",
)

type Acc:
    items: List[Int]

// An interface operation changes a caller's value through a `var` parameter.
interface Step:
    var fn step(value: Int, var out: Acc) Unit!

type Doubler:
    count: Int

impl Step for Doubler:
    var fn step(value: Int, var out: Acc) Unit!:
        self.count += 1
        out.items.append(value * 2)

// Declares `var` but only reads it: the caller's value is unchanged.
type Reader:
    seen: Int

impl Step for Reader:
    var fn step(value: Int, var out: Acc) Unit!:
        self.seen += out.items.length() + value

type Holder:
    step: Step
    acc: Acc

impl Holder:
    // The argument is a field of the receiver's owner: it changes in place.
    var fn run(value: Int) Unit!:
        return self.step.step(value, var self.acc)

test "a var parameter on an interface operation writes back to a local":
    var acc = Acc([])
    var d: Step = Doubler(0)
    for i in 0..3: try d.step(i, var acc)

    var r: Step = Reader(0)
    try r.step(5, var acc)
    try expect_equal(acc.items, [0, 2, 4])

test "a var field argument writes back to its record":
    var h = Holder(Doubler(0), Acc([1]))
    try h.run(4)
    try h.run(5)
    try expect_equal(h.acc.items, [1, 8, 10])

// Writes each word of a line, and the count of words at the end.
type Words:
    count: Int

impl Transform[String, String] for Words:
    var fn step(value: String, var out: List[String]) Unit!:
        for word in value.split(" "):
            self.count += 1
            out.append(word)

    var fn finish(var out: List[String]) Unit!:
        out.append("{self.count}")

test "a transform writes zero or more items per input and more at the end":
    words := through[String, String](from_list(["a b", "", "c"]), Words(0))
    try expect_equal(try collect(words), ["a", "b", "", "c", "4"])

// Writes an item, then fails on a negative input.
type Checked:
    unused: Bool = false

impl Transform[Int, Int] for Checked:
    var fn step(value: Int, var out: List[Int]) Unit!:
        out.append(value)
        if value < 0: return error(Error("negative", kind: "EBADMSG"))

    var fn finish(var out: List[Int]) Unit!:
        return ok(unit)

test "a failed step's partial output is dropped and the failure is the next item":
    var s = through[Int, Int](from_list([1, -2, 3]), Checked())
    var seen: List[Int] = []
    var failed = false

    while true:
        item := s.next()

        if item.is_error():
            failed = true
            break

        if item.get().is_none(): break

        seen.append(item.get().get(0))

    try expect_equal(seen, [1])
    try expect_equal(failed, true)
