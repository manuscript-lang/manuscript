// conform: tags=optional,try-result,tier-io
// conform: phase=run
// conform: origin=thread/type-checker-bug-bash
import stdout from "@std/io/io.ms"

interface Parser[T]:
	fn parse(s String) T!

type IntP:
	base Int = 10

fn IntP.parse(s String) Int!:
	return ok_or(s.parse_int(), Error("missing"))

fn run[T](p Parser[T], s String) T!:
	return p.parse(s)

fn all[T Clonable](p Parser[T], xs List[String]) List[T]!:
	var out = List[T]()
	for x in xs:
		out.append(p.parse(x)?)
	return ok(out)

type Cb:
	f fn(Int) Int!

fn apply(c Cb, x Int) Int!:
	return c.f(x)

fn main() Void:
	p := IntP()
	r := run[Int](p, "42")
	stdout().write(f"{r.get_or(0)}\n").get()

	l := all[Int](p, ["1", "2", "x"])
	stdout().write(f"{l.is_ok()}\n").get()

	l2 := all[Int](p, ["1", "2"])
	stdout().write(f"{l2.get_or([]).length()}\n").get()

	c := Cb(fn x: ok(x + 1))
	stdout().write(f"{apply(c, 1).get_or(0)}\n").get()
