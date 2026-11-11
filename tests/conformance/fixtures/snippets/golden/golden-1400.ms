// conform: tags=diagnostics
// conform: phase=check
import StringBuilder from "@std/string.ms"
import Closeable from "@std/cleanup.ms"
type Resource:
    visits: List[Int]
impl Closeable for Resource:
    fn close() Unit:
        self.visits.append(1)
