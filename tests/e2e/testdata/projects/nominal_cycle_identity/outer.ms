import Wrapper, make_wrapper from "./bridge.ms"

export type Node:
    wrapped: Wrapper

export fn exercise(path: String) Unit:
    let held = Node(make_wrapper(path))
    let _borrowed_path = held.wrapped.node.door.path
