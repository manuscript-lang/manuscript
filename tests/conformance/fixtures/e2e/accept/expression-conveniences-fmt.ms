# conform: tags=aliasing,closures,control-flow,faults,formatter,generics,interfaces,interpolation,lists,maps,match,modules,mutation,optional,parser,records,stdlib-cleanup,stdlib-errors,stdlib-testing,strings,testing,tier-stdlib,try-result,with-cleanup
# conform: phase=parse
# conform: origin=tests/e2e/testdata/accept/expression-conveniences.ms
from "@std/core.ms" import TextError
from "@std/testing.ms" import expect_equal, expect_false, expect_true
from "@std/core.ms" import Closeable

type Counter:
    count: Int

type Resource:
    counter: Counter

impl Closeable for Resource:
    var def close() -> Unit:
        self.counter.count = self.counter.count + 1

def identity[T](value: T) -> T: return value

def amount(text: String, counter: Counter) -> Result[Int, TextError]:
    with Resource(counter: counter) as resource:
        let cents = match text.parse_int():
            case some(value):
                value
            case none:
                return error(cause: TextError("Invalid amount"))

        return ok(value: cents + 1)

def early(value: Optional[Int]) -> Int:
    let number = match value:
        case some(number): number
        case none: return 9

    return number + 1

def all_return(value: Optional[Int]) -> Int:
    let unreachable = match value:
        case some(number): return number
        case none: return 9

def tick(var counter: Counter) -> Result[Int, Error]:
    counter.count | try expect_equal(1)
    counter.count = counter.count + 1
    return ok(0)

def values(var counter: Counter) -> List[Int]:
    counter.count = counter.count + 1
    return [7, 8]

test "indexing and generic applications coexist":
    let items = [10, 20]
    let index = 1
    let indices = [0, 1]
    var counter = Counter(count: 0)
    ((items[0] != 10 or items[index] != 20 or items[-1] != 20)) | try expect_false
    (items[indices[index]] != 20 or items[index - 1] != 10) | try expect_false
    (items[counter.count] != 10 or [items][0][1] != 20) | try expect_false
    (values(var counter) [(try tick(var counter))] != 7 or counter.count != 2) | try expect_false
    identity[Int](items[0]) | try expect_equal(10)

    let callbacks: List[Callable[[Int], Int]] = [identity[Int]]
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
    (f"\u{e000}" < f"\u{10000}") | try expect_true

    let sorted = ["z", "a", "b"].sorted(
        lambda (left: String, right: String) -> Int:
            if left < right: return -1
            if left > right: return 1

            return 0
    )

    sorted | try expect_equal(["a", "b", "z"])

test "match expressions preserve returns and cleanup":
    let present: Optional[Int] = some(value: 4)
    let absent: Optional[Int] = none
    (early(present) != 5 or early(absent) != 9 or all_return(present) != 4) | try expect_false

    let counter = Counter(count: 0)
    let parsed = amount(text: "3", counter: counter)
    (parsed != Result[Int, TextError].ok(value: 4) or counter.count != 1) | try expect_false

    let invalid = amount(text: "invalid", counter: counter)
    (
        (
            invalid != Result[Int, TextError].error(
                cause: TextError("Invalid amount")
            )
            or counter.count != 2
        )
    ) | try expect_false

    let nested = match present:
        case some(value):
            # manuscript:allow-nested-match regression for nested expression values and the absent branch
            match absent:
                case some(other): value + other
                case none: value
        case none: 0

    nested | try expect_equal(4)

    let contextual: List[Int] = match absent:
        case some(value): [value]
        case none: []

    contextual.length() | try expect_equal(0)

    let result = identity[Int](
        match present:
            case some(value): value
            case none: 0
    )
    result | try expect_equal(4)

    let callback = lambda (value: Optional[Int]) -> Int:
        let number = match value:
            case some(number): number
            case none: return 42

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
    let present: Optional[Int] = some(value: 5)

    let result = match present:
        case some(value):
            let doubled = value * 2
            doubled + 1
        case none: 0

    result | try expect_equal(11)

    var count = 0

    while True:
        count = count + 1

        match present:
            case some(value):
                if count < value: continue

                break
            case none: break

    count | try expect_equal(5)

test "contextual values infer from later arms":
    let present: Optional[Int] = some(value: 5)

    let optional = match present:
        case none: none
        case some(value): some(value: value)

    optional.get() | try expect_equal(5)

    let list = match present:
        case none: []
        case some(value): [value]

    list[0] | try expect_equal(5)

def returned_argument(var counter: Counter) -> Result[Int, Error]:
    let absent: Optional[Int] = none
    return ok(
        combine(
            first: match absent:
                case some(value): value
                case none: return ok(17)
            ,
            second: (try tick(var counter))
        )
    )

def combine(first: Int, second: Int) -> Int: return first + second

def propagated(text: String) -> Result[Int, TextError]:
    let result = match text.parse_int():
        case some(value):
            try Result[Int, TextError].ok(value: value)
        case none:
            try Result[Int, TextError].error(cause: TextError("missing"))

    return ok(value: result)

def returned_loop(value: Optional[Int]) -> Int:
    var index = 0

    while True:
        if index > 1: return 23

        match value:
            case some(number):
                index = index + 1
                continue
            case none: break

    return 24

test "expression exits preserve caller boundaries and evaluation order":
    var counter = Counter(count: 0)
    ((try returned_argument(var counter)) != 17 or counter.count != 0) | try expect_false
    propagated("3") | try expect_equal(Result[Int, TextError].ok(value: 3))
    propagated("no") | try expect_equal(
        Result[Int, TextError].error(cause: TextError("missing"))
    )

    let present: Optional[Int] = some(value: 1)
    let absent: Optional[Int] = none
    (returned_loop(present) != 23 or returned_loop(absent) != 24) | try expect_false

    var iterations = 0

    while True:
        let value = match present:
            case some(number):
                while iterations < 3:
                    iterations = iterations + 1
                    if iterations == 2: continue
                    if iterations == 3: break
                number
            case none: break

        if value == 1: break

    iterations | try expect_equal(3)

def condition_exit(value: Optional[Int]) -> Int:
    while True:
        while (
            match value:
                case some(number): True
                case none: break
        ):
            return 1

    return 2

test "match in a loop header exits its lexical enclosing loop":
    let absent: Optional[Int] = none
    condition_exit(absent) | try expect_equal(2)

test "indexing preserves zero and nested optionals":
    let numbers = [0]
    (numbers[0] != 0 or numbers.get(0, default: 99) != 0) | try expect_false

    let nested: List[Optional[Int]] = [none, some(value: 0)]
    (nested[0].is_some() or nested[1].get() != 0) | try expect_false

def observed_optional(var counter: Counter) -> Optional[Int]:
    counter.count = counter.count + 1
    return some(value: 5)

test "match evaluates its input once and only the selected arm":
    var counter = Counter(count: 0)

    let result = match observed_optional(var counter):
        case some(value):
            counter.count = counter.count + 10
            value + 1
        case none:
            counter.count = counter.count + 100
            0

    (result != 6 or counter.count != 11) | try expect_false

def inline_match(value: Optional[Int]) -> Int: match value:
    case some(number): number
    case none: 0

test "match composes with inferred callbacks and map literals":
    let values: List[Optional[Int]] = [some(3), none]
    let mapped = values.map(
        lambda value: match value:
            case some(number): number + 1
            case none: 0
    )
    (mapped[0] != 4 or mapped[1] != 0) | try expect_false

    let lookup = {
        "value": match values[0]:
            case some(number): number
            case none: 0
    }
    lookup.get("value").get() | try expect_equal(3)
    (inline_match(none) != 0 or inline_match(some(5)) != 5) | try expect_false
