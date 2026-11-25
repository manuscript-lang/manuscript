// conform: tags=mutation,lists,control-flow,tier-core
// conform: phase=run
// A change that is followed by `break` or `return` in its own block ends the loop, so the list is not read again.
import stdout from "@std/io/io.ms"

fn first_b(var xs List[String]) Int {
	for x in xs {
		if x == "b" {
			xs.append("d")
			break
		}
	}
	for x in xs {
		if x == "c" {
			xs = ["z"]
			return xs.length()
		}
	}
	return xs.length()
}

fn main() Void {
	var copy = ["a", "b"]
	var seen = List[String]()
	for x in copy {
		seen.append(x.clone())
	}
	for x in copy.clone() {
		copy.append(x)
	}
	for i in 0..copy.length() {
		copy.append("q")
	}
	n := first_b(["a", "b", "c"])
	stdout().write(f"{copy.length()} {seen.length()} {n}\n").get()
}
