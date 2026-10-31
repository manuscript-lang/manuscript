import TextError from "@std/core.ms"
import expect_equal, expect_false, expect_ok, expect_true from "@std/test.ms"
import Closeable from "@std/core.ms"
import filesystem from "@std/fs.ms"

type Counter:
    count: Int

type Resource:
    marker: String

# Cleanup runs on the resource's own copy, so a marker file is how a caller observes it.
impl Closeable for Resource:
    var fn close() Unit!:
        let _written = filesystem().write_file(self.marker, "closed", true)
        return ok(unit)

fn closed(marker: String) Bool: filesystem().read_file(marker).is_ok()

fn identity[T](value: T) T: return value

fn amount(text: String, marker: String) Int!TextError:
    let _resource = Resource(marker: marker.clone())

    let cents = match text.parse_int():
        value:
            value
        none:
            return error(cause: TextError("Invalid amount"))

    return ok(value: cents + 1)

fn early(value: Int?) Int:
    let number = match value:
        number: number
        none: return 9

    return number + 1

fn all_return(value: Int?) Int:
    let _unreachable = match value:
        number: return number
        none: return 9

fn tick(var counter: Counter) Int!:
    counter.count | try expect_equal(1)
    counter.count = counter.count + 1
    return ok(0)

fn values(var counter: Counter) List[Int]:
    counter.count = counter.count + 1
    return [7, 8]

test "indexing and generic applications coexist":
    let items = [10, 20]
    let index = 1
    let indices = [0, 1]
    var counter = Counter(count: 0)
    ((items[0] != 10 or items[index] != 20 or items[-1] != 20)) | try expect_false
    (items[indices[index]] != 20 or items[index - 1] != 10) | try expect_false
    (items[counter.count] != 10 or [items.clone()][0][1] != 20) | try expect_false
    (values(var counter)[(try tick(var counter))] != 7 or counter.count != 2) | try expect_false
    identity[Int](items[0]) | try expect_equal(10)

    let callbacks: List[fn(Int) Int] = [identity[Int]]
    (callbacks[0](2) != 2 or callbacks[indices[0]](3) != 3) | try expect_false

test "empty list constructors have fresh typed storage":
    var empty = List[String]()
    let contextual: List[Int] = List()
    let other = List[String]()
    empty.append("a")
    (empty[0] != "a" or other.length() != 0 or contextual.length() != 0) | try expect_false

    let map = Map[String, Int]()
    map.length() | try expect_equal(0)

test "string concatenation and scalar ordering":
    let lines = ["a", "b"]
    (lines.join("\n") + "\n") | try expect_equal("a\nb\n")
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

    sorted | try expect_equal(["a", "b", "z"])

test "match expressions preserve returns and cleanup":
    let present: Int? = 4
    let absent: Int? = none
    (early(present) != 5 or early(absent) != 9 or all_return(present) != 4) | try expect_false

    let fs = filesystem()
    var temporary = fs.temporary("manuscript-match-") | try expect_ok
    let dir = temporary.path()
    let parsed = amount(text: "3", marker: "{dir}/parsed")
    (parsed != Result[Int, TextError].ok(value: 4)) | try expect_false
    closed("{dir}/parsed") | try expect_true

    let invalid = amount(text: "invalid", marker: "{dir}/invalid")
    (invalid != Result[Int, TextError].error(cause: TextError("Invalid amount"))) | try expect_false
    closed("{dir}/invalid") | try expect_true
    try temporary.close()

    let nested = match present:
        value:
            # manuscript:allow-nested-match regression for nested expression values and the absent branch
            match absent:
                other: value + other
                none: value
        none: 0

    nested | try expect_equal(4)

    let contextual: List[Int] = match absent:
        value: [value]
        none: []

    contextual.length() | try expect_equal(0)

    let result = identity[Int](
        match present:
            value: value
            none: 0
    )
    result | try expect_equal(4)

    let callback = fn(value: Int?) Int:
        let number = match value:
            number: number
            none: return 42

        return number

    callback(absent) | try expect_equal(42)

test "indexes read elements and get supplies defaults":
    let values = [1, 2]
    values.get(2, default: 0) | try expect_equal(0)
    values.get(-3, default: 0) | try expect_equal(0)
    values.get(-9223372036854775808, default: 0) | try expect_equal(0)
    (values[0] != values.get(0) or values[-1] != values.get(-1)) | try expect_false
    List[Int]().get(0, default: 7) | try expect_equal(7)

test "match blocks produce their final value":
    let present: Int? = 5

    let result = match present:
        value:
            let doubled = value * 2
            doubled + 1
        none: 0

    result | try expect_equal(11)

    var count = 0

    while true:
        count = count + 1

        match present:
            value:
                if count < value: continue

                break
            none: break

    count | try expect_equal(5)

test "contextual values infer from later arms":
    let present: Int? = 5

    let optional: Int? = match present:
        none: none
        value: value

    optional.get() | try expect_equal(5)

    let list = match present:
        none: []
        value: [value]

    list[0] | try expect_equal(5)

fn returned_argument(var counter: Counter) Int!:
    let absent: Int? = none
    return ok(
        combine(
            first: match absent:
                value: value
                none: return ok(17)
            ,
            second: (try tick(var counter))
        )
    )

fn combine(first: Int, second: Int) Int: return first + second

fn propagated(text: String) Int!TextError:
    let result = match text.parse_int():
        value:
            try Result[Int, TextError].ok(value: value)
        none:
            try Result[Int, TextError].error(cause: TextError("missing"))

    return ok(value: result)

fn returned_loop(value: Int?) Int:
    var index = 0

    while true:
        if index > 1: return 23

        match value:
            _number:
                index = index + 1
                continue
            none: break

    return 24

test "expression exits preserve caller boundaries and evaluation order":
    var counter = Counter(count: 0)
    ((try returned_argument(var counter)) != 17 or counter.count != 0) | try expect_false
    propagated("3") | try expect_equal(Result[Int, TextError].ok(value: 3))
    propagated("no") | try expect_equal(
        Result[Int, TextError].error(cause: TextError("missing"))
    )

    let present: Int? = 1
    let absent: Int? = none
    (returned_loop(present) != 23 or returned_loop(absent) != 24) | try expect_false

    var iterations = 0

    while true:
        let value = match present:
            number:
                while iterations < 3:
                    iterations = iterations + 1
                    if iterations == 2: continue
                    if iterations == 3: break
                number
            none: break

        if value == 1: break

    iterations | try expect_equal(3)

fn condition_exit(value: Int?) Int:
    while true:
        while (
            match value:
                _number: true
                none: break
        ):
            return 1

    return 2

test "match in a loop header exits its lexical enclosing loop":
    let absent: Int? = none
    condition_exit(absent) | try expect_equal(2)

test "indexing preserves zero and nested optionals":
    let numbers = [0]
    (numbers[0] != 0 or numbers.get(0, default: 99) != 0) | try expect_false

    let nested: List[Int?] = [none, 0]
    (nested[0].is_some() or nested[1].get() != 0) | try expect_false

fn observed_optional(var counter: Counter) Int?:
    counter.count = counter.count + 1
    return 5

test "match evaluates its input once and only the selected arm":
    var counter = Counter(count: 0)

    let result = match observed_optional(var counter):
        value:
            counter.count = counter.count + 10
            value + 1
        none:
            counter.count = counter.count + 100
            0

    (result != 6 or counter.count != 11) | try expect_false

fn inline_match(value: Int?) Int: match value:
    number: number
    none: 0

test "match composes with inferred callbacks and map literals":
    let values: List[Int?] = [3, none]
    let mapped = values.map(
        fn value: match value:
            number: number + 1
            none: 0
    )
    (mapped[0] != 4 or mapped[1] != 0) | try expect_false

    let lookup = {
        "value": match values[0]:
            number: number
            none: 0
    }
    lookup["value"] | try expect_equal(3)
    (inline_match(none) != 0 or inline_match(5) != 5) | try expect_false
