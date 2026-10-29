# conform: tags=diagnostics,interfaces,tier-stdlib
# conform: phase=check
# conform: origin=issue-1923
import Iterator from "@std/core.ms"
import {Deque, DequeIter} from "@std/deque.ms"

fn take(it: Iterator[String]) Int:
    return 0

export fn main() Int:
    var d = Deque[String]()
    var it = d.iter()
    return take(it)
