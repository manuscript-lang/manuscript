import {parse, from_int, BigInt, BigIntError} from "@std/bigint.ms"
import Optional from "@std/optional.ms"
import Result from "@std/result.ms"
import panic from "@std/faults.ms"
import value from "./support/results.ms"

test "big integers exceed machine range without losing precision":
    let big = value(parse(text: "9223372036854775808", radix: 10))
    if not big.to_int().is_none(): return panic("overflow conversion")
    if big.subtract(from_int(1)).to_int() != some(value: 9223372036854775807): return panic("exact subtraction")
    if from_int(7).multiply(from_int(6)).to_string(radix: 10) != "42": return panic("multiply")
    if value(from_int(-7).divide(from_int(3))).to_int() != some(value: -2): return panic("signed divide")
    if value(from_int(-7).remainder(from_int(3))).to_int() != some(value: -1): return panic("signed remainder")
    if from_int(5).bit_xor(from_int(3)).to_int() != some(value: 6): return panic("bitwise xor")

test "big integers validate digits budgets and zero divisors":
    let invalid: Result[BigInt, BigIntError] = error(cause: BigIntError.InvalidInput)
    if from_int(1).divide(from_int(0)) != invalid: return panic("zero divisor")
    let limited: Result[BigInt, BigIntError] = error(cause: BigIntError.LimitExceeded)
    if parse(text: "123", radix: 10, max_digits: some(value: 2)) != limited: return panic("digit limit")
    let malformed: Result[BigInt, BigIntError] = error(cause: BigIntError.InvalidData)
    if parse(text: "1_0", radix: 10) != malformed: return panic("malformed digits")
