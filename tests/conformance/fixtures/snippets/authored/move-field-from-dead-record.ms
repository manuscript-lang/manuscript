// conform: tags=records,lists,scope-cleanup
// conform: phase=run
// conform: origin=copyelim type.release
import stdout from "@std/io/io.ms"

type Pair {
	left List[String]
	right List[String]
	tag String
}

fn left_of(p Pair) List[String] => p.left.clone()

fn tag_of(p Pair) String => p.tag.clone()

fn make(n Int) Pair {
	var l = List[String]()
	var r = List[String]()

	for i in 0..n {
		l.append(f"l{i}")
		r.append(f"r{i}")
	}

	return Pair(l, r, f"t{n}")
}

fn main() Void {
	l := left_of(make(3))
	t := tag_of(make(2))
	stdout().write(f"{l.join(",")} {t}\n").get()
}
