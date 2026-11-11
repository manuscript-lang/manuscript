// conform: tags=diagnostics
// conform: phase=check
import (
    List, // keep
    ListBuilder,
) from "@std/collections/collections.ms"
fn count() Int: ListBuilder[Int]().freeze().length()+List[Int]().length()
