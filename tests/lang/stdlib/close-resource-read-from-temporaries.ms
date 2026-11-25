// conform: tags=scope-cleanup,records,interfaces,tier-io
// conform: phase=run
// conform: origin=value-semantics-audit
import Closeable from "@std/core.ms"

// A temporary holding a resource that is only read closes it once, at the end of its
// statement.
type Door {
	name String
}

fn move Door.close() Void! {
	print(f"closed {self.name}")
}

interface Labeled {
	fn label() String
}

fn Door.label() String {
	return self.name.clone()
}

type Pair {
	a Door
	b Door
}

fn maybe(n String) Door? {
	return Door(n.clone())
}

fn doors() List[Door] {
	return [Door("l1"), Door("l2")]
}

fn pair() Pair {
	return Pair(Door("pa"), Door("pb"))
}

fn show(l Labeled) String {
	return l.label()
}

fn main() Void {
	present := maybe("optional") != null
	print("--list")

	second := doors()[1].label()
	print("--field")

	first := pair().a.label()
	print("--interface")

	shown := show(Door("converted"))
	print(f"end {present} {second} {first} {shown}")
}
// expect-exit: 0
// expect-stdout: closed optional
// expect-stdout: --list
// expect-stdout: closed l2
// expect-stdout: closed l1
// expect-stdout: --field
// expect-stdout: closed pb
// expect-stdout: closed pa
// expect-stdout: --interface
// expect-stdout: closed converted
// expect-stdout: end true l2 pa converted
