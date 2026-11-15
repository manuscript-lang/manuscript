// Values exchanged with the server, in PostgreSQL's text format.
import (
	Bytes from "@std/bytes.ms",
	hex_decode, hex_encode from "@std/data/encoding.ms",
)

// A query parameter or a result column.
export enum Value:
	Null
	Bool(value: Bool)
	Int(value: Int)
	Float(value: Float)
	Text(value: String)
	Bytes(value: Bytes)

fn Value.as_text() String?:
	match self:
		Value.Null: return none
		Value.Bool(value): return if value: "t" else: "f"
		Value.Int(value): return "{value}"
		Value.Float(value): return "{value}"
		Value.Text(value): return value.clone()
		Value.Bytes(value): return "\\x{hex_encode(value)}"

// The text-format bytes sent for a parameter; none is NULL.
export fn encode_value(value: Value) Bytes?:
	text := value.as_text()
	if text.is_none(): return none

	return text.get("").to_bytes()

// Decodes one column from its text form, by the column's type OID.
export fn decode_value(type_oid: Int, raw: Bytes?) Value!:
	if raw.is_none(): return ok(Value.Null)

	text := raw.get(Bytes([])).decode_utf8().get("")
	if type_oid == 16: return ok(Value.Bool(text == "t"))
	if type_oid == 20 or type_oid == 21 or type_oid == 23 or type_oid == 26:
		return ok(Value.Int(text.parse_int().get(0)))
	if type_oid == 700 or type_oid == 701:
		return ok(Value.Float(text.parse_float().get(0.0)))
	if type_oid == 17:
		return ok(Value.Bytes(hex_decode(text.slice(2, text.length())?, none)?))

	return ok(Value.Text(text))
