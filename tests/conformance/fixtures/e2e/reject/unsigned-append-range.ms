// conform: tags=testing,tier-stdlib
// conform: phase=check
import BytesBuilder from "@std/bytes.ms"

fn build() Void {
	var out = BytesBuilder()
	out.append(256)
	out.append(-1)
	out.append_uint16_le(65536)
}
