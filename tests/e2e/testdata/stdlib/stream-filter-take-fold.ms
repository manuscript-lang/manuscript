import expect_equal, expect_error from "@std/test/test.ms"
import Source, ReadStream from "@std/io/io.ms"
import from_list, filter, take, fold, collect, map from "@std/io/streams.ms"

// An endless source that counts how many items were pulled.
type Counting:
    next_value: Int
    pulled: Int

impl Source[Int] for Counting:
    var fn next() Int?!:
        self.pulled += 1
        self.next_value += 1
        return ok(self.next_value)

    var fn close() Unit!:
        return ok(unit)

test "filter keeps matching items in order":
    let kept = try collect(
        from_list([1, 2, 3, 4, 5, 6]) | filter(fn x: x % 2 == 0), none
    )
    try expect_equal(kept, [2, 4, 6])
    try expect_equal(
        try collect(from_list([1, 3]) | filter(fn x: x % 2 == 0), none), List[Int]()
    )

test "take stops after count items and never reads past them":
    let first = try collect(ReadStream[Int](Counting(0, 0)) | take(3), none)
    try expect_equal(first, [1, 2, 3])
    try expect_equal(try collect(from_list([1, 2]) | take(5), none), [1, 2])
    try expect_equal(try collect(from_list([1, 2]) | take(0), none), List[Int]())
    try expect_equal(try collect(from_list([1, 2]) | take(-1), none), List[Int]())

test "fold combines items from a start value":
    try expect_equal(try fold(from_list([1, 2, 3, 4]), 10, fn s, x: s + x), 20)
    try expect_equal(try fold(from_list(List[Int]()), 7, fn s, x: s + x), 7)

test "stages compose over an endless stream":
    let out = try collect(
        ReadStream[Int](Counting(0, 0)) | filter(fn x: x > 2) | map(
            fn x: x * 10
        ) | take(3),
        none
    )
    try expect_equal(out, [30, 40, 50])

// Every odd read fails; successful reads yield 2, 4, 6, ... without ending.
type Intermittent:
    calls: Int = 0

impl Source[Int] for Intermittent:
    var fn next() Int?!:
        self.calls += 1
        if self.calls % 2 == 1: return error(Error("retry this read", kind: "EAGAIN"))

        return ok(self.calls)

    var fn close() Unit!:
        return ok(unit)

test "take does not spend its last item on a failed read":
    var source = ReadStream[Int](Intermittent()) | take(1)
    let reason = source.next() | try expect_error
    try expect_equal(reason, Error("retry this read", kind: "EAGAIN"))
    try expect_equal(try source.next(), 2)
    try expect_equal(try source.next(), none)
    try expect_equal(try source.next(), none)

test "take preserves its remaining items across errors in composed stages":
    var source = ReadStream[Int](Intermittent()) | filter(fn x: x % 4 == 0) | map(
        fn x: x * 10
    ) | take(2)

    for expected in [40, 80]:
        for failed in 0..2:
            let reason = source.next() | try expect_error
            try expect_equal(reason, Error("retry this read", kind: "EAGAIN"))

        try expect_equal(try source.next(), expected)

    // The endless input's next call would fail; the exhausted taker must not pull it.
    try expect_equal(try source.next(), none)
    try expect_equal(try source.next(), none)
