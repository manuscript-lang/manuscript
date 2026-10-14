import {
    parse_timestamp,
    parse_timestamp_format,
    timestamp,
    Timestamp,
    TimeError
} from "@std/time.ms"
import Result from "@std/result.ms"
import panic from "@std/faults.ms"
import value from "./support/results.ms"

test "timestamp reference layouts preserve nanoseconds and normalize offsets":
    let stamp = value(parse_timestamp("2024-02-29T10:20:30.123456789Z"))
    let layout = "2006-01-02 15:04:05.000000000 -07:00"
    let format = stamp.format
    if format(layout) != "2024-02-29 10:20:30.123456789 +00:00": return panic(
        "stored timestamp format"
    )
    if value(
        parse_timestamp_format(
            text: format(layout),
            layout: layout
        )
    ) != stamp: return panic("layout round trip")
    if (
        value(
            parse_timestamp_format(
                text: "2024-02-29 12:20:30.123456789 +02:00",
                layout: layout
            )
        ) != stamp
    ): return panic("offset normalization")
    if stamp.format("date: 2006-01-02") != "date: 2024-02-29": return panic(
        "literal layout text"
    )
    if stamp.format("") != "": return panic("empty format")
    if (
        value(
            parse_timestamp_format(text: "2024-02-29", layout: "2006-01-02")
        ).to_string() != "2024-02-29T00:00:00Z"
    ): return panic("date uses UTC midnight")

test "timestamp layout parsing preserves typed errors and calendar range":
    let invalid_layout: Result[Timestamp, TimeError] = error(TimeError.InvalidInput)
    let invalid_text: Result[Timestamp, TimeError] = error(TimeError.InvalidData)
    let range: Result[Timestamp, TimeError] = error(TimeError.OutOfRange)
    if parse_timestamp_format(text: "", layout: "") != invalid_layout: return panic(
        "empty parse layout"
    )
    if parse_timestamp_format(text: "2024-02-30", layout: "2006-01-02") != invalid_text: return panic(
        "invalid calendar date"
    )
    if (
        parse_timestamp_format(
            text: "2024-02-29 trailing",
            layout: "2006-01-02"
        ) != invalid_text
    ): return panic("trailing text")
    if parse_timestamp_format(text: "00:00:00", layout: "15:04:05") != range: return panic(
        "missing year"
    )
    if (
        parse_timestamp_format(
            text: "0001-01-01T00:00:00+01:00",
            layout: "2006-01-02T15:04:05Z07:00"
        ) != range
    ): return panic("UTC boundary range")

    let epoch = value(timestamp(seconds: 0, nanoseconds: 7))
    if (
        epoch.format(
            "2006-01-02T15:04:05.000000000Z07:00"
        ) != "1970-01-01T00:00:00.000000007Z"
    ): return panic("epoch precision")
