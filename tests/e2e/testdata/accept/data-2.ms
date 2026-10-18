import panic from "@std/faults.ms"
import Bytes from "@std/bytes.ms"

test "explicit byte conversion":
    if not ("é".byte_length() == 2):
        return panic("check failed")
    if not ("é".to_bytes().to_string() == some("é")):
        return panic("check failed")

    let invalid: Optional[String] = none
    if not (Bytes([255]).to_string() == invalid):
        return panic("check failed")
    if not ("-007".parse_int() == some(-7)):
        return panic("check failed")
