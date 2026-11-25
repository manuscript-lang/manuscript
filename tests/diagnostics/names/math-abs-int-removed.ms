// conform: tags=testing,tier-stdlib
// conform: phase=check
import abs_int from "@std/math/math.ms"

export fn main() Int {
	return abs_int(-3)
}
// expect-error: MS2002 3:8-3:15 module does not export abs_int; @std/math/math.ms exports: BigInt, BinaryFloatParts, DivMod, FloatParts, WideProduct, WordDifference, WordDivision, WordSum, acos, acosh, add_with_carry, asin, ...; namespace imports are unsupported, so import individual exports with 'import Name, OtherName from "@std/math/math.ms"'
// expect-error: MS2001 6:12 unknown binding abs_int; declare it with 'abs_int := ...' before use, define 'fn abs_int(...) T { ... }', or import it from a module
