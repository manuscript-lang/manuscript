// conform: tags=diagnostics
// conform: phase=check
import List from "@std/collections/collections.ms"  // keep

fn count() Int => List[Int]().length()
// expect-error: MS2003 3:8-3:12 redundant prelude import List; remove List from this import and use its prelude declaration directly
// expect-fix: 3:1-3:51 ""
