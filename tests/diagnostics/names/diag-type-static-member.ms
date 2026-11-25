// conform: tags=diagnostics,types,tier-core
// conform: phase=check
// conform: origin=bug bash: BigInt.from_int(...) reported an empty case list
import BigInt from "@std/math/math.ms"

export fn main() Int {
	b := BigInt.from_int(2)
	return b.to_int().get(0)
}
// expect-error: MS2001 7:17 BigInt has no cases or static members, so `BigInt.from_int(...)` does not exist; if from_int is a module function, import it and call from_int(...); if it is a method, call it on a value
