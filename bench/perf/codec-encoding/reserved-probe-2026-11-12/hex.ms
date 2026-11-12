import Bytes from "@std/bytes.ms"

export fn hex_encode(data: Bytes) String:
	length := data.length()
	if length == 0: return ""

	var out = List[UInt8](reserve: length * 2)
	digits: List[UInt8] := [
		48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 97, 98, 99, 100, 101, 102
	]

	for byte in data.values():
		n := byte.to_int()
		out.append(digits[n / 16])
		out.append(digits[n % 16])

	return Bytes(out).decode_utf8().get("")
