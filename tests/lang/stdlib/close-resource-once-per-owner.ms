// conform: tags=scope-cleanup,records,interfaces,tier-io
// conform: phase=run
// conform: origin=value-semantics-audit
import Closeable from "@std/core.ms"

// Each resource closes exactly once, whichever owner holds it when its scope ends.
type Door {
	name String
}

fn move Door.close() Void! {
	print(f"closed {self.name}")
}

type Pair {
	door Door
}

fn say(s String) Void {
	print(f"{s}")
}

fn doors() Map[String, Door] {
	var m Map[String, Door] = {}
	m.add("a", Door("map-a"))
	return m
}

fn open(n String) Door!Error {
	return ok(Door(n.clone()))
}

fn collect() List[Door]!Error {
	var found = List[Door]()
	first := open("try-move")
	found.append(first?)

	second := open("try-read")
	say(f"read {(second?).name}")
	return ok(found)
}

fn main() Void {
	count := doors().length()
	say("--result")

	opened := open("result").is_ok()
	say("--try")

	found := collect().get()
	say("--closeable")

	_held Closeable := Door("closeable")
	many List[Closeable] := [Door("list")]
	say("--map of records")

	var pairs Map[String, Pair] = {}
	pairs.add("p", Pair(Door("pair")))
	say(f"end {count} {opened} {found.length()} {many.length()} {pairs.length()}")
}
// expect-exit: 0
// expect-stdout: closed map-a
// expect-stdout: --result
// expect-stdout: closed result
// expect-stdout: --try
// expect-stdout: read try-read
// expect-stdout: closed try-read
// expect-stdout: --closeable
// expect-stdout: --map of records
// expect-stdout: end 1 true 1 1 1
// expect-stdout: closed pair
// expect-stdout: closed list
// expect-stdout: closed closeable
// expect-stdout: closed try-move
