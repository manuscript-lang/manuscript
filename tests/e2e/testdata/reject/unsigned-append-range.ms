from "@std/bytes.ms" import BytesBuilder

def build() -> Unit:
    var out = BytesBuilder()
    out.append(256)
    out.append(-1)
    out.append_uint16_le(65536)
