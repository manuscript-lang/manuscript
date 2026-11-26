// conform: tags=stdlib,tier-stdlib
// conform: phase=run
import big_int_of_int from "@std/math/math.ms"
import memory_usage from "@std/os/system.ms"

// A BigInt temporary a statement only reads is freed after its last use, also in the
// program entry. `lastuse` once treated it as a handle that may close something, so each
// one stayed live to the end of `main` and its drop was repeated on every later unwind path.
fn main() Void {
	one := big_int_of_int(1)
	before := memory_usage().get().resident
	a := one.shift_left(16000000 + 1).get().sign()
	b := one.shift_left(16000000 + 2).get().sign()
	c := one.shift_left(16000000 + 3).get().sign()
	d := one.shift_left(16000000 + 4).get().sign()
	e := one.shift_left(16000000 + 5).get().sign()
	f := one.shift_left(16000000 + 6).get().sign()
	g := one.shift_left(16000000 + 7).get().sign()
	h := one.shift_left(16000000 + 8).get().sign()
	i := one.shift_left(16000000 + 9).get().sign()
	j := one.shift_left(16000000 + 10).get().sign()
	k := one.shift_left(16000000 + 11).get().sign()
	l := one.shift_left(16000000 + 12).get().sign()
	m := one.shift_left(16000000 + 13).get().sign()
	n := one.shift_left(16000000 + 14).get().sign()
	o := one.shift_left(16000000 + 15).get().sign()
	p := one.shift_left(16000000 + 16).get().sign()
	grown := memory_usage().get().resident - before
	print(a + b + c + d + e + f + g + h + i + j + k + l + m + n + o + p)
	print(grown < 12000000)
}
