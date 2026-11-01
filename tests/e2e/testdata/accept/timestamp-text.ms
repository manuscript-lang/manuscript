import timestamp, parse_timestamp from "@std/os/time.ms"
import expect_equal from "@std/test/test.ms"

test "timestamp text pads and trims fractions across UTC boundaries":
    for nanos in [0, 1, 9, 10, 99, 100, 99999999, 100000000, 250000000, 999999999]:
        for seconds in [-62135596800, -1, 0, 1710073815, 253402300799]:
            let value = timestamp(seconds, nanos).get()
            try expect_equal(parse_timestamp(value.to_string()).get(), value)

    try expect_equal(
        timestamp(-62135596800, 0).get().to_string(), "0001-01-01T00:00:00Z"
    )
    try expect_equal(
        timestamp(0, 1).get().to_string(), "1970-01-01T00:00:00.000000001Z"
    )
    try expect_equal(
        timestamp(0, 10).get().to_string(), "1970-01-01T00:00:00.00000001Z"
    )
    try expect_equal(
        timestamp(0, 100000000).get().to_string(), "1970-01-01T00:00:00.1Z"
    )
    try expect_equal(
        timestamp(253402300799, 999999999).get().to_string(),
        "9999-12-31T23:59:59.999999999Z"
    )
