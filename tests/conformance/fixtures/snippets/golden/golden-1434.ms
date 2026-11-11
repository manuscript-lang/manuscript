// conform: tags=diagnostics
// conform: phase=check
import Closeable from "@std/cleanup.ms"
type Resource:
    visits: List[Int]
impl Closeable for Resource:
    fn close() Unit:
        self.visits.append(1)
