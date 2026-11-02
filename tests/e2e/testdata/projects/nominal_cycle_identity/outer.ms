import Wrapper, make_wrapper from "./bridge.ms"
import Shared from "@std/concurrency/shared.ms"

export type Node:
    wrapped: Wrapper

export fn exercise(log: Shared[List[Int]]) Unit:
    let held = Node(make_wrapper(log))
    let _borrowed_log = held.wrapped.node.door.log
