// conform: tags=mutation,maps,control-flow,tier-core
// conform: phase=run
// A loop over a map's keys reads key storage only: changing a value in place leaves the keys alone.
import stdout from "@std/io/io.ms"

fn bump(var n Int) Void {
	n += 1
}

fn main() Void {
	var m = Map[String, Int]()
	m["a"] = 1
	m["b"] = 2
	for key in m.keys() {
		bump(m[key])
	}
	m.for_each((key, var n) => bump(n))
	stdout().write(f"{m["a"]} {m["b"]}\n").get()
}
// expect-exit: 0
// expect-stdout: 3 4
