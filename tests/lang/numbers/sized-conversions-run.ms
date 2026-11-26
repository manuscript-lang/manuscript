// conform: tags=numbers,types,tier-core
// conform: phase=run
// conform: origin=sized numeric types stage 2
import stdout from "@std/io/io.ms"

fn main() Void {
	a Int8 := -100
	b Int32 := 70000
	big Int := 5000000000
	void stdout().write(
		f"{a.to_int32() + b} {a.to_int64()} {b.to_int8()} {b.to_int16()} {big.to_int32()} {big.to_int64()}\n"
	)
	void stdout().write(
		f"{a.to_float()} {b.to_float32()} {big.to_float32()} {a.compare(-99)} {b.to_hex()}\n"
	)

	f Float32 := 0.1
	g Float := 0.1
	void stdout().write(
		f"{f.to_float64()} {g.to_float32()} {f.is_nan()} {f.compare(f)} {f.truncate_to_int()} {(2.5).to_float32()}\n"
	)
	void stdout().write(f"{a.to_decimal()}\n")
}
// expect-exit: 0
// expect-stdout: 69900 -100 none none none 5000000000
// expect-stdout: -100 70000 5000000000 -1 11170
// expect-stdout: 0.10000000149011612 some(0.1) false 0 some(0) some(2.5)
// expect-stdout: -100
