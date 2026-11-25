// conform: tags=generics,tier-core
// conform: phase=run
// A payload-less case of a generic enum takes its type arguments from the expected type or the other arguments.
import stdout from "@std/io/io.ms"

enum Opt[T] {
	Has(v T)
	None
}

enum Either[A, B] {
	Left(a A)
	Right(b B)
	Neither
}

type Box {
	o Opt[Int]
}

fn pick[T](o Opt[T], d T) T {
	return match o {
		Opt.Has(v) => v
		Opt.None => d
	}
}

fn first(flag Bool) Opt[String] {
	if flag {
		return Opt.None
	}
	return Opt.Has("x")
}

fn both[A, B](e Either[A, B], a A, b B) Int {
	return 7
}

fn main() Void! {
	a := pick(Opt.None, 3)
	box := Box(o: Opt.None)
	xs List[Opt[Int]] := [Opt.None, Opt.Has(2)]
	ys := [Opt.Has(1), Opt.None]
	r := both(Either.Neither, "s", 4)
	var m Opt[Int] = Opt.Has(1)
	m = Opt.None
	name := pick(first(true), "none")
	stdout().write(f"{a} {r} {xs.length()} {ys.length()} {pick(box.o, 5)} {pick(m, 6)} {name}\n")?
}
