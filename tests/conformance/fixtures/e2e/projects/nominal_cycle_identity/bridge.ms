import Node, make_inner from "./inner.ms"

export type Wrapper:
	node: Node

export fn make_wrapper(path: String) Wrapper:
	return Wrapper(make_inner(path))
