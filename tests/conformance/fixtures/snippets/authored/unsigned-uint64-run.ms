// conform: tags=numbers,types,tier-core
// conform: phase=run
// conform: origin=unsigned integer types stage 2
import stdout from "@std/io/io.ms"

type Stamp:
	id UInt64
	tag UInt8

fn mix(h UInt64, b UInt64) UInt64:
	return (h * 31 + b) % 18446744073709551557

fn main() Void:
	max UInt64 := 18446744073709551615
	half UInt64 := 9223372036854775808
	one UInt64 := 1
	void stdout().write(f"{max} {half} {one}\n")
	void stdout().write(
		f"{max > half} {half > one} {one < max} {max >= max} {half <= one} {max == max}\n"
	)
	void stdout().write(f"{max / 2} {max % 10} {half - 1 + half == max} {max - half}\n")
	void stdout().write(
		f"{max.compare(one)} {one.compare(max)} {half.to_hex()} {max.to_binary().length()}\n"
	)
	void stdout().write(
		f"{max.to_float()} {half.to_decimal()} {max.to_int()} {one.to_int()} {max.to_uint32()} {one.to_uint8()}\n"
	)

	l List[UInt64] := [max, 5, half, 0]
	void stdout().write(f"{l.sorted()} {l.sorted().reversed()}\n")

	s := Stamp(id: max, tag: 7)
	big Int := 5
	void stdout().write(f"{s.id} {s.tag} {big.to_uint64()} {(-big).to_uint64()}\n")

	var h UInt64 = 7
	for i in 0..10:
		h = mix(h, i.to_uint64() or 0)
	void stdout().write(f"{h}\n")
