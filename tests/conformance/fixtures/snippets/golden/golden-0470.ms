// conform: tags=diagnostics
// conform: phase=check
import List, Map, Set from "@std/collections/collections.ms"
fn get() Int: List[Int]().length()+Map[Int,Int]().length()+Set[Int]().length()
