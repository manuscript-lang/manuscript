// conform: tags=testing,tier-stdlib
// conform: phase=test
import (
	Bytes, BytesBuilder from "@std/bytes.ms",
	parse, stringify from "@std/data/json.ms",
	expect_equal, expect_error from "@std/test/test.ms",
)

test "typed JSON Base64 decodes every byte and preserves strict syntax":
	var bytes = BytesBuilder()
	for value in 0..256: bytes.append(value.to_uint8().get())

	expected := [Bytes([]), Bytes([0]), Bytes([251, 255]), bytes.build()]
	text := stringify(expected)?
	expect_equal((parse[List[Bytes]](text)?), expected)?
	expect_equal((parse[Bytes]("\"+/8=\"")?), Bytes([251, 255]))?
	for encoded in ["-_8=", "Zh==", "Zm9=", "=AAA", "AA=A", "éAA", "Zg== "]:
		expect_equal((expect_error(parse[Bytes]("\"{encoded}\""))?).kind, "EBADMSG")?
