import Bytes from "@std/bytes.ms"

fn probe(data: Bytes, at: Int) Int:
	if data.is_empty(): return -1
	return data.length() + data.get(at).to_int()

fn main() Void:
	print(probe("ab".to_bytes(), 1))
