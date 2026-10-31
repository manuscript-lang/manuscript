import Bytes from "@std/bytes.ms"
import expect_equal from "@std/test.ms"

test "byte search preserves offsets across scanner boundaries":
    let needles: List[UInt8] = [0, 1, 128, 255]

    for value in needles:
        for size in [0, 1, 7, 8, 15, 16, 31, 32, 33, 63, 64, 65, 127, 128, 129]:
            let empty_hits = "a".repeat(size).get().to_bytes()
            try expect_equal(empty_hits.index_of_byte(value, 0), none)

            for at in 0..size:
                let data = empty_hits.with_value(at, value)
                try expect_equal(data.index_of_byte(value, -1), at)
                try expect_equal(data.index_of_byte(value, at), at)
                if at >= 17: try expect_equal(data.index_of_byte(value, 1), at)
                try expect_equal(data.index_of_byte(value, at + 1), none)
                try expect_equal(data.index_of_byte(value, size), none)
                try expect_equal(data.index_of_byte(value, size + 1), none)

test "byte search returns the earliest hit at or after start":
    let data = Bytes([255, 0, 255, 128, 255])
    try expect_equal(data.index_of_byte(255, 0), 0)
    try expect_equal(data.index_of_byte(255, 1), 2)
    try expect_equal(data.index_of_byte(255, 3), 4)
    try expect_equal(data.index_of_byte(255, -9223372036854775807 - 1), 0)
    try expect_equal(data.index_of_byte(255, 9223372036854775807), none)
