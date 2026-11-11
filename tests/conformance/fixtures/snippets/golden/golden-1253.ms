// conform: tags=diagnostics
// conform: phase=check
import Bytes from "@std/bytes.ms"
fn extract(data: Bytes) List[UInt8]:
    bound: fn() List[UInt8] := data.values
    return data.values()
