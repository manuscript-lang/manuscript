import expect_equal from "@std/test/test.ms"
import Source, stream from "@std/io/io.ms"
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
    let first = try collect(stream[Int](Counting(0, 0)) | take(3), none)
    try expect_equal(first, [1, 2, 3])
    try expect_equal(try collect(from_list([1, 2]) | take(5), none), [1, 2])
    try expect_equal(try collect(from_list([1, 2]) | take(0), none), List[Int]())
    try expect_equal(try collect(from_list([1, 2]) | take(-1), none), List[Int]())

test "fold combines items from a start value":
    try expect_equal(try fold(from_list([1, 2, 3, 4]), 10, fn s, x: s + x), 20)
    try expect_equal(try fold(from_list(List[Int]()), 7, fn s, x: s + x), 7)

test "stages compose over an endless stream":
    let out = try collect(
        stream[Int](Counting(0, 0)) | filter(fn x: x > 2) | map(
            fn x: x * 10
        ) | take(3),
        none
    )
    try expect_equal(out, [30, 40, 50])
