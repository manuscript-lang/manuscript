// conform: tags=testing,tier-stdlib
// conform: phase=check
import BytesBuilder from "@std/bytes.ms"

fn build() Void {
	var out = BytesBuilder()
	out.append(256)
	out.append(-1)
	out.append_uint16_le(65536)
}
// expect-error: MS3070 7:16 literal 256 is out of range for UInt8; use a value between 0 and 255
// expect-error: MS3070 8:17 literal -1 is out of range for UInt8; use a value between 0 and 255
// expect-error: MS3070 9:26 literal 65536 is out of range for UInt16; use a value between 0 and 65535
