import {expect_equal, expect_false, expect_true} from "@std/testing.ms"
import Closeable from "@std/cleanup.ms"

type Counter:
    count: Int

type Resource:
    counter: Counter

impl Closeable for Resource:
    fn close() Unit:
        self.counter.count = self.counter.count + 1

fn identity[T](value: T) T: return value

fn amount(text: String, counter: Counter) Result[Int, String]:
    with resource = Resource(counter: counter):
        let cents = match text.parse_int():
            some(value):
                value
            none:
                return error(cause: "Invalid amount")

        return ok(value: cents + 1)

fn early(value: Optional[Int]) Int:
    let number = match value:
        some(number): number
        none: return 9

    return number + 1

fn all_return(value: Optional[Int]) Int:
    let unreachable = match value:
        some(number): return number
        none: return 9

fn tick(counter: Counter) Result[Int, Error]:
    counter.count | try expect_equal(expected: 1)
    counter.count = counter.count + 1
    return ok(0)

fn values(counter: Counter) List[Int]:
    counter.count = counter.count + 1
    return [7, 8]

test "indexing and generic applications coexist":
    let items = [10, 20]
    let index = 1
    let indices = [0, 1]
    let counter = Counter(count: 0)
    ((items[0].get() != 10 or items[index].get() != 20 or items[-1].get() != 20)) | try expect_false
    (items[indices[index].get()].get() != 20 or items[index - 1].get() != 10) | try expect_false
    (items[counter.count].get() != 10 or [items][0].get() [1].get() != 20) | try expect_false
    (values(counter) [(try tick(counter))].get() != 7 or counter.count != 2) | try expect_false
    identity[Int](items[0].get()) | try expect_equal(expected: 10)
    let callbacks: List[fn(value: Int) Int] = [identity[Int]]
    (callbacks[0].get()(2) != 2 or callbacks[indices[0].get()].get()(3) != 3) | try expect_false

test "empty list constructors have fresh typed storage":
    let empty = List[String]()
    let contextual: List[Int] = List()
    let other = List[String]()
    empty.append("a")
    (empty[0].get() != "a" or other.length() != 0 or contextual.length() != 0) | try expect_false
    let map = Map[String, Int]()
    map.length() | try expect_equal(expected: 0)

test "string concatenation and scalar ordering":
    let lines = ["a", "b"]
    (lines.join("\n") + "\n") | try expect_equal(expected: "a\nb\n")
    (("" < "a" and "a" < "aa" and "é" > "z" and "a" <= "a" and "a" >= "a")) | try expect_true
    ("a" < "a" or "a" > "a" or "b" <= "a" or "a" >= "b") | try expect_false
    ("" + "value" != "value" or "value" + "" != "value") | try expect_false
    ("\u{e000}" < "\u{10000}") | try expect_true
    let sorted = ["z", "a", "b"].sorted(
        fn(left: String, right: String) Int:
            if left < right: return -1
            if left > right: return 1

            return 0
    )
    sorted | try expect_equal(expected: ["a", "b", "z"])

test "match expressions preserve returns and cleanup":
    let present: Optional[Int] = some(value: 4)
    let absent: Optional[Int] = none
    (early(present) != 5 or early(absent) != 9 or all_return(present) != 4) | try expect_false
    let counter = Counter(count: 0)
    let parsed = amount(text: "3", counter: counter)
    (parsed != Result[Int, String].ok(value: 4) or counter.count != 1) | try expect_false
    let invalid = amount(text: "invalid", counter: counter)
    (
        (
            invalid != Result[Int, String].error(cause: "Invalid amount")
            or counter.count != 2
        )
    ) | try expect_false

    let nested = match present:
        some(value):
            # manuscript:allow-nested-match regression for nested expression values and the absent branch
            match absent:
                some(other): value + other
                none: value
        none: 0

    nested | try expect_equal(expected: 4)

    let contextual: List[Int] = match absent:
        some(value): [value]
        none: []

    contextual.length() | try expect_equal(expected: 0)
    let result = identity[Int](
        match present:
            some(value): value
            none: 0
    )
    result | try expect_equal(expected: 4)
    let callback = fn(value: Optional[Int]) Int:
        let number = match value:
            some(number): number
            none: return 42

        return number
    callback(absent) | try expect_equal(expected: 42)

test "missing indexes are optional":
    let values = [1, 2]
    (
        (
            values[2].is_some()
            or values[-3].is_some()
            or values[-9223372036854775808].is_some()
        )
    ) | try expect_false
    (values[0] != values.at(0) or values[-1] != values.at(-1)) | try expect_false
    List[Int]() [0].is_some() | try expect_false

test "match blocks produce their final value":
    let present: Optional[Int] = some(value: 5)

    let result = match present:
        some(value):
            let doubled = value * 2
            doubled + 1
        none: 0

    result | try expect_equal(expected: 11)
    var count = 0

    while true:
        count = count + 1

        match present:
            some(value):
                if count < value: continue

                break
            none: break

    count | try expect_equal(expected: 5)

test "contextual values infer from later arms":
    let present: Optional[Int] = some(value: 5)

    let optional = match present:
        none: none
        some(value): some(value: value)

    optional.get() | try expect_equal(expected: 5)

    let list = match present:
        none: []
        some(value): [value]

    list[0].get() | try expect_equal(expected: 5)

fn returned_argument(counter: Counter) Result[Int, Error]:
    let absent: Optional[Int] = none
    return ok(
        combine(
            first: match absent:
                some(value): value
                none: return ok(17)
            ,
            second: (try tick(counter))
        )
    )

fn combine(first: Int, second: Int) Int: return first + second

fn propagated(text: String) Result[Int, String]:
    let result = match text.parse_int():
        some(value):
            try Result[Int, String].ok(value: value)
        none:
            try Result[Int, String].error(cause: "missing")

    return ok(value: result)

fn returned_loop(value: Optional[Int]) Int:
    var index = 0

    while true:
        if index > 1: return 23

        match value:
            some(number):
                index = index + 1
                continue
            none: break

    return 24

test "expression exits preserve caller boundaries and evaluation order":
    let counter = Counter(count: 0)
    ((try returned_argument(counter)) != 17 or counter.count != 0) | try expect_false
    propagated("3") | try expect_equal(expected: Result[Int, String].ok(value: 3))
    propagated("no") | try expect_equal(
        expected: Result[Int, String].error(cause: "missing")
    )
    let present: Optional[Int] = some(value: 1)
    let absent: Optional[Int] = none
    (returned_loop(present) != 23 or returned_loop(absent) != 24) | try expect_false
    var iterations = 0

    while true:
        let value = match present:
            some(number):
                while iterations < 3:
                    iterations = iterations + 1
                    if iterations == 2: continue
                    if iterations == 3: break
                number
            none: break

        if value == 1: break

    iterations | try expect_equal(expected: 3)

fn condition_exit(value: Optional[Int]) Int:
    while true:
        while (
            match value:
                some(number): true
                none: break
        ):
            return 1

    return 2

test "match in a loop header exits its lexical enclosing loop":
    let absent: Optional[Int] = none
    condition_exit(absent) | try expect_equal(expected: 2)

test "indexing preserves zero and nested optionals":
    let numbers = [0]
    (numbers[0].is_none() or numbers[0].get(99) != 0) | try expect_false
    let nested: List[Optional[Int]] = [none, some(value: 0)]
    (nested[0].is_none() or nested[0].get().is_some()) | try expect_false
    (nested[1].get().get() != 0 or nested[2].is_some()) | try expect_false

fn observed_optional(counter: Counter) Optional[Int]:
    counter.count = counter.count + 1
    return some(value: 5)

test "match evaluates its input once and only the selected arm":
    let counter = Counter(count: 0)

    let result = match observed_optional(counter):
        some(value):
            counter.count = counter.count + 10
            value + 1
        none:
            counter.count = counter.count + 100
            0

    (result != 6 or counter.count != 11) | try expect_false

fn inline_match(value: Optional[Int]) Int: match value:
    some(number): number
    none: 0

test "match composes with inferred callbacks and map literals":
    let values: List[Optional[Int]] = [some(3), none]
    let mapped = values.map(
        fn(value): match value:
            some(number): number + 1
            none: 0
    )
    (mapped[0].get() != 4 or mapped[1].get() != 0) | try expect_false
    let lookup = {
        "value": match values[0].get():
            some(number): number
            none: 0
    }
    lookup.get("value").get() | try expect_equal(expected: 3)
    (inline_match(none) != 0 or inline_match(some(5)) != 5) | try expect_false
