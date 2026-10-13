import panic from "@std/faults.ms"
import {parse_int, parse_float} from "@std/numbers.ms"
import Hashable from "@std/equality.ms"
import {List, Map, Set} from "@std/collections.ms"
import {read_float, write_float, read_float64, write_float64} from "@std/binary.ms"
import Bytes from "@std/bytes.ms"
import Decimal from "@std/decimal.ms"

type NarrowRecord:
    count: Int
    fraction: Float

fn identity[T](value: T) -> T: value

fn hash_value[T: Hashable](value: T) -> Int: value.hash()

test "default scalar arithmetic and collection boundaries":
    let minimum = -2147483648
    let maximum = 2147483647
    if minimum % -1 != 0 or maximum * 0 != 0:
        return panic("default limits")

    let values = [identity(1), 2, 3]
    if values.fold(
        0,
        fn(total, value): total + value
    ) != 6:
        return panic("generic default boxes")

    let record = NarrowRecord(3, 0.1)
    if record.clone() != record or some(record.count).unwrap() != 3:
        return panic("record or alternative identity")

    let keys: Map[Int, String] = {- 2147483648: "minimum", 3: "three"}
    if keys.get(minimum).unwrap() != "minimum" or hash_value(3) != 3.hash():
        return panic("hash width/equality")
    if not Set[Int]().with_value(3).contains(3):
        return panic("default set")

test "binary32 precision rounding and IEEE results":
    let rounded = 16777216.0 + 1.0
    if rounded != 16777216.0 or 16777217.to_float() != 16777216.0:
        return panic("default precision")

    let fused = 1.0001220703125 * 0.9998779296875 - 1.0
    if fused != 0.0: return panic("operator rounding")
    if 1e-45 <= 0.0 or 1e-45 / 2.0 != 0.0:
        return panic("subnormal rounding")

    let negative_zero = -0.0
    let nan = 0.0 / 0.0
    if "{negative_zero}" != "-0" or "{1.0 / negative_zero}" != "-Infinity":
        return panic("signed zero")
    if (
        nan == nan
        or nan <= 0.0
        or not nan.is_nan()
    ):
        return panic("NaN")

    let default_fraction = 0.1
    let wide_fraction: Float64 = 0.1
    if default_fraction.to_float64() == wide_fraction or "{default_fraction}" != "0.1":
        return panic("context must choose precision before parsing")
    if default_fraction.to_float64() != 0.10000000149011612:
        return panic("widening must retain prior binary32 rounding")

test "explicit conversions check the truncated destination and round directly":
    let negative_fraction: Float64 = -2147483648.5
    let positive_fraction: Float64 = 2147483647.5
    let too_large: Int64 = 2147483648
    if negative_fraction.truncate_to_int().unwrap() != -2147483648:
        return panic("truncate before range check")
    if (
        positive_fraction.truncate_to_int().unwrap() != 2147483647
        or too_large.to_int().is_some()
    ):
        return panic("checked destination range")

    let trap: Int64 = 4611686293305294849
    if trap.to_float().to_float64() != 4611686568183201792.0:
        return panic("integer conversion double rounded")
    if trap.to_float64().to_float().to_float64() != 4611686018427387904.0:
        return panic("rounding trap lost")
    if 2147483648d.truncate_to_int().is_some() or 0.1d.to_float() != 0.1:
        return panic("Decimal destination width")

test "default parsers and binary wire width":
    if parse_int("2147483648", 10).is_ok() or parse_float("1e39").is_ok():
        return panic("default parser range")
    if parse_int("-2147483648", 10).unwrap() != -2147483648:
        return panic("default minimum parser")

    let bytes = write_float(0.1, true)
    if (
        bytes != Bytes([205, 204, 204, 61])
        or read_float(bytes, 0, true).unwrap() != 0.1
    ):
        return panic("binary32 wire")

    let precise: Float64 = 0.1
    let wide_bytes = write_float64(precise, true)
    if (
        wide_bytes.length() != 8
        or read_float64(wide_bytes, 0, true).unwrap() != precise
    ):
        return panic("binary64 wire")
