// conform: tags=diagnostics
// conform: phase=check
import Bytes from "@std/bytes.ms"
fn count(items: List[Int], data: Bytes) Int:
    return items.length() + data.length()
