// conform: tags=decimal,tier-core
// conform: phase=run
import Decimal, parse_decimal from "@std/math/decimal.ms"

fn main() Void! {
	a := parse_decimal("1.50")?
	b := a.clone()
	print(b.to_string())
	print([a.clone()] == [a.clone()])

	var counts = Map[Decimal, Int]()
	counts.add(a.clone(), 1)
	print(counts.length())
	return ok(void)
}
// expect-exit: 0
// expect-stdout: 1.5
// expect-stdout: true
// expect-stdout: 1
