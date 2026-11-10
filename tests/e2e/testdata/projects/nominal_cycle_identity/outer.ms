import Wrapper, make_wrapper from "./bridge.ms"

export type Node:
    wrapped: Wrapper

export fn exercise(path: String) Unit:
    held := Node(make_wrapper(path))
    _borrowed_path := held.wrapped.node.door.path
