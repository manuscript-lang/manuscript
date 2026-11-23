// conform: tags=interfaces,scope-cleanup,tier-core
// conform: phase=run
// A resource viewed as an interface leaves no box behind: the callee that consumes an
// interface value frees its box, and a view of a resource a binding keeps frees only
// the view's box (run with MS_FREE_AT_EXIT=1 and mimalloc stats to see the live block
// count).
import Closeable from "@std/core.ms"

type Door:
	name: String

fn move Door.close() Void!:
	print(f"closed {self.name}")

interface Labeled:
	fn label() String

fn Door.label() String:
	return self.name.clone()

fn use(move c: Closeable) Int:
	return 1

fn show(l: Labeled) String:
	return l.label()

fn main() Void:
	print(use(Door("moved")))

	kept := Door("kept")
	print(show(kept))
	print(show(Door("temporary")))
	print("end")
