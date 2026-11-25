// conform: tags=diagnostics
// conform: phase=check
import List, Map, Set from "@std/collections/collections.ms"

fn get() Int => List[Int]().length() + Map[Int, Int]().length() + Set[Int]().length()
// expect-error: MS2003 3:8-3:12 redundant prelude import List; remove List from this import and use its prelude declaration directly
// expect-fix: 3:8-3:14 ""
// expect-error: MS2003 3:14-3:17 redundant prelude import Map; remove Map from this import and use its prelude declaration directly
// expect-fix: 3:14-3:19 ""
// expect-error: MS2003 3:19-3:22 redundant prelude import Set; remove Set from this import and use its prelude declaration directly
// expect-fix: 3:17-3:22 ""
