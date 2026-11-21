import Bytes from "@std/bytes.ms"

fn c(b: Bytes) UInt8:
	return b[0]

fn d(b: Bytes) Int:
	return b[1].to_int() + b[-1].to_int()

fn e(s: String) Int:
	x := s[0]
	return 1

fn main() Int:
	return d("ab".to_bytes())
