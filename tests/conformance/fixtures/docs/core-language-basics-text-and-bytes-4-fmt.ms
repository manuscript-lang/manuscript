# conform: tags=control-flow,faults,formatter,modules,optional,parser,stdlib-bytes,stdlib-faults,strings,testing,tier-stdlib
# conform: phase=parse
# conform: origin=documentation/core-language/basics/text-and-bytes.md:110
from "@std/core.ms" import panic
from "@std/bytes.ms" import Bytes

test "explicit byte conversion":
    if not ("é".byte_length() == 2):
        return panic("check failed")
    if not ("é".to_bytes().decode_utf8() == some("é")):
        return panic("check failed")

    let invalid: Optional[String] = none
    if not (Bytes([255]).decode_utf8() == invalid):
        return panic("check failed")
    if not ("-007".parse_int() == some(-7)):
        return panic("check failed")
