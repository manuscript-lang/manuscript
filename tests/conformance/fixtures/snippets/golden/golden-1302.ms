// conform: tags=diagnostics
// conform: phase=check
import panic from "@std/core.ms"

type Node:
	value Int
	next Node?

fn read(node Node) Int:
	return (node.next or panic("called Optional.get() on null")).value
