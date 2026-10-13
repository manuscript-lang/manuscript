import panic from "@std/faults.ms"
import Decimal from "@std/decimal.ms"
import parse_int64 from "@std/numbers.ms"
import parse_float64 from "@std/numbers.ms"
import Equal from "@std/equality.ms"
import Set from "@std/collections.ms"

type WideRecord:
    count: Int64
    measure: Float64

fn identity[T](value: T) -> T:
    return value

fn equal_value[T: Equal](left: T, right: T) -> Bool:
    return left.equals(Equal(right))

test "explicit wide literals arithmetic and boundaries":
    let largest: Int64 = 9223372036854775807
    let smallest: Int64 = -9223372036854775808
    if largest - 1 != 9223372036854775806 or smallest + 1 != -9223372036854775807:
        return panic("wide boundaries changed")
    if (
        -7 / 2 != -3
        or - 7 % 3 != -1
        or smallest % -1 != 0
    ):
        return panic("wide division or remainder changed")

    let product: Int64 = 3000000000 * 2
    if product != 6000000000:
        return panic("wide arithmetic was narrowed")
    if (
        3.to_int64() != 3
        or 3.to_float64() != 3.0
        or 3.5.to_float64() != 3.5
    ):
        return panic("explicit widening changed")

    let three: Int64 = 3
    let fraction: Float64 = 3.5
    let above_maximum: Float64 = 9223372036854775808.0
    let minimum_float: Float64 = -9223372036854775808.0
    if three.to_decimal() != 3d or three.to_string(16) != "3":
        return panic("wide formatting or decimal conversion changed")
    if three.to_int().unwrap() != 3 or fraction.truncate_to_int().unwrap() != 3:
        return panic("explicit integer conversion changed")
    if (
        fraction.truncate_to_int64().unwrap() != 3
        or 3.5.truncate_to_int64().unwrap() != 3
    ):
        return panic("wide truncation changed")
    if (
        above_maximum.truncate_to_int64().is_some()
        or minimum_float.truncate_to_int64().unwrap() != smallest
    ):
        return panic("wide float boundary conversion changed")
    if smallest.toString() != "-9223372036854775808":
        return panic("wide minimum formatting changed")

test "wide values retain generic collection record and alternative identity":
    let values: List[Int64] = [3000000000, identity(4000000000)]
    let sum: Int64 = values.fold(
        0,
        fn(total, value): total + value
    )
    if sum != 7000000000 or values[0].unwrap() != 3000000000:
        return panic("wide list or generic payload changed")

    let keys: Map[Int64, String] = {3000000000: "first"}
    keys.add(3000000000, "last")
    if keys.length() != 1 or keys.get(3000000000).unwrap() != "last":
        return panic("wide map equality and hashing disagree")

    let original = WideRecord(count: sum, measure: 1e300)
    let copy = original.clone()
    if (
        copy != original
        or copy.count != 7000000000
        or copy.measure != 1e300
    ):
        return panic("wide record or clone changed")

    let optional: Optional[Int64] = some(sum)
    if identity(optional).unwrap() != sum:
        return panic("wide alternative changed")

test "binary64 rounds each operation and retains IEEE outcomes":
    let rounded: Float64 = 1.0000000074505806 * 0.9999999925494194 - 1.0
    if rounded != 0.0:
        return panic("binary64 operators were fused")

    let nan: Float64 = 0.0 / 0.0
    if (
        not nan.is_nan()
        or nan == nan
        or nan < 0.0
        or nan > 0.0
    ):
        return panic("wide NaN rules changed")

    let infinite: Float64 = 1.0 / 0.0
    if (
        infinite.is_finite()
        or infinite.to_string() != "Infinity"
        or infinite.truncate_to_int64().is_some()
    ):
        return panic("wide infinity rules changed")

    let negative_zero: Float64 = -0.0
    if (
        negative_zero != 0.0
        or negative_zero.toString() != "-0"
        or (1.0 / negative_zero).to_string() != "-Infinity"
    ):
        return panic("wide signed zero changed")

    let tiny: Float64 = 5e-324
    let precise: Float64 = 1.5
    if tiny.to_string() != "5e-324" or (tiny / 2.0).to_string() != "0":
        return panic("wide subnormal rounding changed")
    if (
        precise.to_fixed(3).unwrap() != "1.500"
        or precise.to_precision(4).unwrap() != "1.500"
    ):
        return panic("wide precision formatting changed")

test "wide parsing skips default-width intermediate values":
    if parse_int64("9223372036854775807", 10).unwrap() != 9223372036854775807:
        return panic("wide parser narrowed integer")
    if parse_int64("9223372036854775808", 10).is_ok() or parse_int64("3", 1).is_ok():
        return panic("wide parser accepted invalid integer")
    if parse_float64("1e300").unwrap() != 1e300 or parse_float64("1e400").is_ok():
        return panic("wide float parser range changed")
    if (
        not parse_float64("NaN").unwrap().is_nan()
        or parse_float64("-0").unwrap().toString() != "-0"
    ):
        return panic("wide parser lost IEEE values")

test "wide equality retains explicit and generic views":
    let integer: Int64 = 3
    let floating: Float64 = 3.0
    if not integer.equals(Equal(integer)) or not floating.equals(Equal(floating)):
        return panic("wide equals method lost its viewed argument")
    if (
        not Equal(integer).equals(Equal(integer))
        or not Equal(floating).equals(Equal(floating))
    ):
        return panic("wide interface receivers lost equality")
    if not equal_value(integer, integer) or not equal_value(floating, floating):
        return panic("generic Equal boundary lost wide equality")

    let keys = Set[Int64]()
    keys.with_value(integer)
    if not keys.contains(integer) or not keys.contains(identity(integer)):
        return panic("wide hash collection membership changed")

fn choose_other[T](left: T, right: T) -> T: left

fn choose_wide[T](value: T, producer: fn(input: Int) -> T) -> T: value

test "fresh nested calls and fully annotated producers receive wide literal context":
    let integer: Optional[Int64] = some(identity(1))
    let fraction: Optional[Float64] = some(identity(0.1))
    let explicit: Optional[Float64] = Optional[Float64].some(identity(0.1))
    let known: Float64 = 0.1
    let from_other = choose_other(
        identity(0.1),
        known
    )
    if from_other != known: return panic("typed argument context was ignored")

    let produced = choose_wide(
        identity(0.1),
        fn(input: Int) -> Float64: 0.1
    )
    if integer.unwrap().to_int().unwrap() != 1:
        return panic("nested integer box did not retain context")
    if (
        fraction.unwrap() != 0.10000000000000001
        or explicit.unwrap() != fraction.unwrap()
    ):
        return panic("nested float was rounded before context")
    if produced != fraction.unwrap():
        return panic("annotated input producer lost its evidence")
