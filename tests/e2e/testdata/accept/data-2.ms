import Bytes from "@std/bytes.ms"
import List from "@std/collections.ms"
import Optional from "@std/optional.ms"

test "explicit byte conversion":
    assert "é".byte_length() == 2
    assert "é".to_bytes().to_text() == some(value: "é")
    let invalid: Optional[String] = none
    assert Bytes(values: [255]).to_text() == invalid
    assert "-007".parse_int() == some(value: -7)
