import Node, make_inner from "./inner.ms"
import Shared from "@std/concurrency/shared.ms"

export type Wrapper:
    node: Node

export fn make_wrapper(log: Shared[List[Int]]) Wrapper:
    return Wrapper(make_inner(log))
