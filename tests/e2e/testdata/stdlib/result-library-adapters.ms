import Bytes, VarintError from "@std/bytes.ms"
import Duration, TimeError, parse_duration from "@std/os/time.ms"
import expect_equal, expect_error, expect_ok from "@std/test/test.ms"

type InputFailure:
    case Binary(cause: VarintError)
    case Time(cause: TimeError)
    case MissingPrefix
    case MissingKey(value: Int)

fn read_number(data: Bytes) UInt64!InputFailure:
    let decoded = try data.uvarint(0).map_error(fn cause: InputFailure.Binary(cause))
    return ok(decoded.value)

fn read_duration(text: String) Duration!InputFailure:
    return parse_duration(text).map_error(fn cause: InputFailure.Time(cause))

fn read_prefixed(text: String) String!InputFailure:
    return text.cut_prefix("name=").ok_or(InputFailure.MissingPrefix)

fn sorted_index(values: List[Int], target: Int) Int!InputFailure:
    let position = values.binary_search(target)
    if not position.found:
        return error(InputFailure.MissingKey(target))

    return ok(position.index)

test "library results compose with failure values without a reporting implementation":
    let number = try expect_ok(read_number(Bytes([172, 2])))
    try expect_equal(number, 300)
    try expect_equal(
        (try expect_error(read_number(Bytes([128])))),
        InputFailure.Binary(VarintError.Incomplete)
    )

    let duration = try expect_ok(read_duration("1.5us"))
    try expect_equal(duration.to_nanoseconds(), 1500)
    try expect_equal(
        (try expect_error(read_duration("invalid"))),
        InputFailure.Time(TimeError.InvalidData)
    )

test "absence adapters and sorted lookup retain an explicit failure type":
    let value = try expect_ok(read_prefixed("name=value"))
    try expect_equal(value, "value")
    try expect_equal(
        (try expect_error(read_prefixed("missing"))), InputFailure.MissingPrefix
    )
    try expect_equal((try expect_ok(sorted_index([1, 3, 3], 3))), 1)
    try expect_equal(
        (try expect_error(sorted_index([1, 3, 3], 2))), InputFailure.MissingKey(2)
    )
