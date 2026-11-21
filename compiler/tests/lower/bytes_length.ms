import Bytes from "@std/bytes.ms"

fn size(data: Bytes) Int:
	return data.length()

fn blank(data: Bytes) Bool:
	return data.is_empty()

fn main() Int:
	if blank("".to_bytes()): return size("abc".to_bytes()) - 3
	return 1
