# conform: tags=records,stdlib-json,testing
# conform: phase=test
import expect_equal from "@std/test.ms"
import parse, stringify, JsonError from "@std/json.ms"

type Sized:
    small: UInt8
    signed: Int8
    wide: UInt64
    single: Float32
    maybe: Optional[UInt16]
    items: List[Int32]

fn sample() Sized:
    let maybe: UInt16 = 7
    let single: Float32 = 0.1
    let low: Int32 = -1
    let high: Int32 = 2
    return Sized(255, -128, 18446744073709551615, single, some(maybe), [low, high])

test "JSON writes sized numbers like Int and Float":
    try expect_equal(
        stringify(sample()),
        ok(
            "\{\"small\":255,\"signed\":-128,\"wide\":18446744073709551615,\"single\":0.1,\"maybe\":7,\"items\":[-1,2]\}"
        )
    )

test "JSON reads sized numbers back":
    let text = stringify(sample()).get()
    let back = parse[Sized](text).get()
    try expect_equal(back.small.to_int(), 255)
    try expect_equal(back.signed.to_int(), -128)
    try expect_equal(back.wide.to_string_radix(16), "ffffffffffffffff")
    try expect_equal(stringify(back).get(), text)

test "JSON rejects sized numbers outside their range":
    let invalid: Result[Sized, JsonError] = error(JsonError.InvalidData)
    let head = "\{\"signed\":0,\"wide\":0,\"single\":0,\"items\":[]"
    try expect_equal(parse[Sized](head + ",\"small\":256\}"), invalid)
    try expect_equal(parse[Sized](head + ",\"small\":-1\}"), invalid)
    try expect_equal(
        parse[Sized](
            "\{\"small\":0,\"signed\":-129,\"wide\":0,\"single\":0,\"items\":[]\}"
        ),
        invalid
    )
    try expect_equal(
        parse[Sized](
            "\{\"small\":0,\"signed\":0,\"wide\":18446744073709551616,\"single\":0,\"items\":[]\}"
        ),
        invalid
    )
    try expect_equal(
        parse[Sized](
            "\{\"small\":0,\"signed\":0,\"wide\":-1,\"single\":0,\"items\":[]\}"
        ),
        invalid
    )
    try expect_equal(
        parse[Sized](
            "\{\"small\":0,\"signed\":0,\"wide\":0,\"single\":1e39,\"items\":[]\}"
        ),
        invalid
    )
    try expect_equal(
        parse[Sized](
            "\{\"small\":0,\"signed\":0,\"wide\":0,\"single\":0,\"items\":[2147483648]\}"
        ),
        invalid
    )
