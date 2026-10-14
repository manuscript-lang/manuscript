import Closeable from "@std/cleanup.ms"
import panic from "@std/faults.ms"

type Counter:
    count: Int

type Resource:
    counter: Counter

impl Closeable for Resource:
    fn close() -> Unit:
        self.counter.count = self.counter.count + 1

fn identity[T](value: T) -> T: return value

fn amount(text: String, counter: Counter) -> Result[Int, String]:
    with resource = Resource(counter: counter):
        let cents = match text.parse_int():
            some(value):
                value

            none:
                return error(cause: "Invalid amount")

        return ok(value: cents + 1)

fn early(value: Optional[Int]) -> Int:
    let number = match value:
        some(number): number
        none: return 9

    return number + 1

fn all_return(value: Optional[Int]) -> Int:
    let unreachable = match value:
        some(number): return number
        none: return 9

fn tick(counter: Counter) -> Int:
    if counter.count != 1: return panic("receiver must evaluate first")

    counter.count = counter.count + 1
    return 0

fn values(counter: Counter) -> List[Int]:
    counter.count = counter.count + 1
    return [7, 8]

test "indexing and generic applications coexist":
    let items = [10, 20]
    let index = 1
    let indices = [0, 1]
    let counter = Counter(count: 0)
    if (
        items[0].unwrap() != 10
        or items[index].unwrap() != 20
        or items[-1].unwrap() != 20
    ):
        return panic("index result")
    if items[indices[index].unwrap()].unwrap() != 20 or items[index - 1].unwrap() != 10:
        return panic("computed index")
    if items[counter.count].unwrap() != 10 or [items][0].unwrap() [1].unwrap() != 20:
        return panic("nested or field index")
    if values(counter) [tick(counter)].unwrap() != 7 or counter.count != 2:
        return panic("index evaluation order")
    if identity[Int](items[0].unwrap()) != 10:
        return panic("generic call")

    let callbacks: List[fn(value: Int) -> Int] = [identity[Int]]
    if callbacks[0].unwrap()(2) != 2 or callbacks[indices[0].unwrap()].unwrap()(3) != 3:
        return panic("indexed callable")

test "empty list constructors have fresh typed storage":
    let empty = List[String]()
    let contextual: List[Int] = List()
    let other = List[String]()
    empty.append("a")
    if (
        empty[0].unwrap() != "a"
        or other.length() != 0
        or contextual.length() != 0
    ):
        return panic("fresh list construction")

    let map = Map[String, Int]()
    if map.length() != 0: return panic("map construction")

test "string concatenation and scalar ordering":
    let lines = ["a", "b"]
    if lines.join("\n") + "\n" != "a\nb\n":
        return panic("concatenation")
    if not (
        "" < "a"
        and "a" < "aa"
        and "é" > "z"
        and "a" <= "a"
        and "a" >= "a"
    ):
        return panic("string ordering")
    if (
        "a" < "a"
        or "a" > "a"
        or "b" <= "a"
        or "a" >= "b"
    ):
        return panic("false string comparisons")
    if "" + "value" != "value" or "value" + "" != "value":
        return panic("empty concatenation")
    if not ("\u{e000}" < "\u{10000}"):
        return panic("Unicode scalar order")

    let sorted = ["z", "a", "b"].sorted(
        fn(left: String, right: String) -> Int:
            if left < right: return -1
            if left > right: return 1

            return 0
    )
    if sorted != ["a", "b", "z"]: return panic("sorting")

test "match expressions preserve returns and cleanup":
    let present: Optional[Int] = some(value: 4)
    let absent: Optional[Int] = none
    if (
        early(present) != 5
        or early(absent) != 9
        or all_return(present) != 4
    ):
        return panic("enclosing returns")

    let counter = Counter(count: 0)
    let parsed = amount(text: "3", counter: counter)
    if parsed != Result[Int, String].ok(value: 4) or counter.count != 1:
        return panic("successful cleanup")

    let invalid = amount(text: "invalid", counter: counter)
    if (
        invalid != Result[Int, String].error(cause: "Invalid amount")
        or counter.count != 2
    ):
        return panic("early return cleanup")

    let nested = match present:
        some(value):
            # manuscript:allow-nested-match regression for nested expression values and the absent branch
            match absent:
                some(other): value + other
                none: value

        none: 0

    if nested != 4: return panic("nested match")

    let contextual: List[Int] = match absent:
        some(value): [value]
        none: []

    if contextual.length() != 0: return panic("contextual arms")

    let result = identity[Int](
        match present:
            some(value): value
            none: 0
    )
    if result != 4: return panic("match argument")

    let callback = fn(value: Optional[Int]) -> Int:
        let number = match value:
            some(number): number
            none: return 42

        return number
    if callback(absent) != 42: return panic("closure return boundary")

test "missing indexes are optional":
    let values = [1, 2]
    if (
        values[2].is_some()
        or values[-3].is_some()
        or values[-9223372036854775808].is_some()
    ):
        return panic("out of range must be none")
    if values[0] != values.at(0) or values[-1] != values.at(-1):
        return panic("index parity")
    if List[Int]() [0].is_some(): return panic("empty indexing")

test "match blocks produce their final value":
    let present: Optional[Int] = some(value: 5)

    let result = match present:
        some(value):
            let doubled = value * 2
            doubled + 1

        none: 0

    if result != 11: return panic("arm block")

    var count = 0

    while true:
        count = count + 1

        match present:
            some(value):
                if count < value: continue

                break

            none: break

    if count != 5: return panic("match loop exits")

test "contextual values infer from later arms":
    let present: Optional[Int] = some(value: 5)

    let optional = match present:
        none: none
        some(value): some(value: value)

    if optional.unwrap() != 5: return panic("optional inference")

    let list = match present:
        none: []
        some(value): [value]

    if list[0].unwrap() != 5: return panic("list inference")

fn returned_argument(counter: Counter) -> Int:
    let absent: Optional[Int] = none
    return combine(
        first: match absent:
            some(value): value
            none: return 17
        ,
        second: tick(counter)
    )

fn combine(first: Int, second: Int) -> Int: return first + second

fn propagated(text: String) -> Result[Int, String]:
    let result = match text.parse_int():
        some(value):
            try Result[Int, String].ok(value: value)

        none:
            try Result[Int, String].error(cause: "missing")

    return ok(value: result)

fn returned_loop(value: Optional[Int]) -> Int:
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
    if returned_argument(counter) != 17 or counter.count != 0:
        return panic("later argument evaluated after return")
    if propagated("3") != Result[Int, String].ok(value: 3):
        return panic("successful propagation")
    if propagated("no") != Result[Int, String].error(cause: "missing"):
        return panic("propagation returned from match instead of function")

    let present: Optional[Int] = some(value: 1)
    let absent: Optional[Int] = none
    if returned_loop(present) != 23 or returned_loop(absent) != 24:
        return panic("return through loop boundary")

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

    if iterations != 3: return panic("nested loop target")

fn condition_exit(value: Optional[Int]) -> Int:
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
    if condition_exit(absent) != 2: return panic("wrong header exit")

test "indexing preserves zero and nested optionals":
    let numbers = [0]
    if numbers[0].is_none() or numbers[0].unwrap_or(99) != 0:
        return panic("zero must be present")

    let nested: List[Optional[Int]] = [none, some(value: 0)]
    if nested[0].is_none() or nested[0].unwrap().is_some():
        return panic("present none must retain both optional layers")
    if nested[1].unwrap().unwrap() != 0 or nested[2].is_some():
        return panic("nested optional indexing")

fn observed_optional(counter: Counter) -> Optional[Int]:
    counter.count = counter.count + 1
    return some(value: 5)

test "match evaluates its input once and only the selected arm":
    let counter = Counter(count: 0)

    let result = match observed_optional(counter):
        some(value):
            counter.count = counter.count + 10
            value + 1

        none: panic("unselected arm ran")

    if result != 6 or counter.count != 11:
        return panic("match evaluation count")

fn inline_match(value: Optional[Int]) -> Int: match value:
    some(number): number
    none: 0

test "match composes with inferred callbacks and map literals":
    let values: List[Optional[Int]] = [some(3), none]
    let mapped = values.map(
        fn(value): match value:
            some(number): number + 1
            none: 0
    )
    if mapped[0].unwrap() != 4 or mapped[1].unwrap() != 0:
        return panic("match callback inference")

    let lookup = {
        "value": match values[0].unwrap():
            some(number): number
            none: 0
    }
    if lookup.get("value").unwrap() != 3:
        return panic("match in map literal")

    if inline_match(none) != 0 or inline_match(some(5)) != 5:
        return panic("inline match result")
