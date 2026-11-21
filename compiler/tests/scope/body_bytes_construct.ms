import Bytes from "@std/bytes.ms"

fn a() Bytes:
	return Bytes([1, 2, 3])

fn b(x: Int) Bytes:
	values := [1, 2, x]
	return Bytes(values)

fn c() Bytes:
	return Bytes(values: [1])
