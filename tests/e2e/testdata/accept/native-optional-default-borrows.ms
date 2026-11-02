import expect_equal from "@std/test/test.ms"

fn heap_text(seed: Int) String:
    return ["heap-backed-payload-before-", seed.to_string(), "-and-after-the-number"].join(
        ""
    )

fn missing_temporary(seed: Int) Int!:
    let absent: Int? = none
    let convert = absent.ok_or[Error]
    return convert(
        Error(
            "missing value at " + heap_text(seed), kind: ErrorCategory.NotFound
        )
    )

fn string_temporary(seed: Int) Int!String:
    let absent: Int? = none
    let convert = absent.ok_or[String]
    return convert(heap_text(seed))

fn fallback_temporary(seed: Int) String:
    let values = List[String]()
    let get = values.get
    return get(0, heap_text(seed))

interface Fallback:
    fn choose(value: String? = none) String

type Choice:
    fallback: String

impl Fallback for Choice:
    fn choose(value: String?) String:
        if let present = value: return present.clone()

        return self.fallback.clone()

test "bound ok_or results own heap-backed temporary causes":
    let missing = missing_temporary(1)
    let text = string_temporary(2)
    let churn = (0..64).map(fn i: heap_text(i + 20))
    try expect_equal(missing.err().message, "missing value at " + heap_text(1))
    try expect_equal(text.err(), heap_text(2))
    try expect_equal(churn.length(), 64)

test "bound ok_or leaves caller causes independent of its result":
    let absent: Int? = none
    let convert = absent.ok_or[Error]
    var cause = Error("missing value at " + heap_text(3), kind: ErrorCategory.NotFound)
    let result = convert(cause)
    cause = Error("missing value at " + heap_text(4), kind: ErrorCategory.NotFound)
    try expect_equal(result.err().message, "missing value at " + heap_text(3))
    try expect_equal(cause.message, "missing value at " + heap_text(4))

    let present: Int? = 0
    let keep = present.ok_or[Error]
    try expect_equal(keep(cause).get(), 0)
    try expect_equal(cause.message, "missing value at " + heap_text(4))

test "bound native get owns selected heap-backed fallback results":
    let result = fallback_temporary(5)
    let values = List[String]()
    let get = values.get
    var fallback = heap_text(6)
    let selected = get(0, fallback)
    fallback = heap_text(7)
    try expect_equal(result, heap_text(5))
    try expect_equal(selected, heap_text(6))
    try expect_equal(fallback, heap_text(7))

test "bound interface adapters preserve heap-backed arguments and results":
    let view: Fallback = Choice(heap_text(8))
    let choose = view.choose
    let result = choose(heap_text(9))
    var argument = heap_text(10)
    let selected = choose(argument)
    argument = heap_text(11)
    try expect_equal(result, heap_text(9))
    try expect_equal(selected, heap_text(10))
    try expect_equal(argument, heap_text(11))
    try expect_equal(choose(), heap_text(8))
    try expect_equal(choose(none), heap_text(8))
