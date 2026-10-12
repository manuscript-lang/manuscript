# Canonical standard-library declarations. Implementations are native.

import Error from "@std/errors.ms"
import Optional from "@std/optional.ms"
import Result from "@std/result.ms"

export type BigIntError:
    case InvalidInput
    case InvalidData
    case LimitExceeded

export type BigInt:
    fn add(right: BigInt) -> BigInt
    fn subtract(right: BigInt) -> BigInt
    fn multiply(right: BigInt) -> BigInt
    fn divide(right: BigInt) -> Result[BigInt, BigIntError]
    fn remainder(right: BigInt) -> Result[BigInt, BigIntError]
    fn compare(right: BigInt) -> Int
    fn bit_and(right: BigInt) -> BigInt
    fn bit_or(right: BigInt) -> BigInt
    fn bit_xor(right: BigInt) -> BigInt
    fn to_int() -> Optional[Int]
    fn to_string(radix: Int) -> String

fn add(left: BigInt, right: BigInt) -> BigInt

fn bit_and(left: BigInt, right: BigInt) -> BigInt

fn bit_or(left: BigInt, right: BigInt) -> BigInt

fn bit_xor(left: BigInt, right: BigInt) -> BigInt

fn compare(left: BigInt, right: BigInt) -> Int

fn divide(left: BigInt, right: BigInt) -> Result[BigInt, BigIntError]

fn format(value: BigInt, radix: Int) -> String

export fn from_int(value: Int) -> BigInt

fn multiply(left: BigInt, right: BigInt) -> BigInt

export fn parse(text: String, radix: Int, max_digits: Optional[Int] = none) -> Result[BigInt, BigIntError]

fn remainder(left: BigInt, right: BigInt) -> Result[BigInt, BigIntError]

fn subtract(left: BigInt, right: BigInt) -> BigInt

fn to_int(value: BigInt) -> Optional[Int]

impl Error for BigIntError:
    fn message() -> String
