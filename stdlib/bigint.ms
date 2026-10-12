# Canonical standard-library declarations. Implementations are native.

import LibraryError from "@std/errors.ms"
import Optional from "@std/optional.ms"
import Result from "@std/result.ms"

export type BigInt

export fn add(left: BigInt, right: BigInt) -> BigInt

export fn bit_and(left: BigInt, right: BigInt) -> BigInt

export fn bit_or(left: BigInt, right: BigInt) -> BigInt

export fn bit_xor(left: BigInt, right: BigInt) -> BigInt

export fn compare(left: BigInt, right: BigInt) -> Int

export fn divide(left: BigInt, right: BigInt) -> Result[BigInt, LibraryError]

export fn format(value: BigInt, radix: Int) -> String

export fn from_int(value: Int) -> BigInt

export fn multiply(left: BigInt, right: BigInt) -> BigInt

export fn parse(text: String, radix: Int, max_digits: Int) -> Result[BigInt, LibraryError]

export fn remainder(left: BigInt, right: BigInt) -> Result[BigInt, LibraryError]

export fn subtract(left: BigInt, right: BigInt) -> BigInt

export fn to_int(value: BigInt) -> Optional[Int]
