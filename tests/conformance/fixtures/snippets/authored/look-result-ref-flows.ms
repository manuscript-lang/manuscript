// conform: tags=ownership,try-result
// conform: phase=run
type Box {
	names List[String]
}

fn hold Box.pick(i Int) &String! {
	if i >= self.names.length() { return error(Error("out of range")) }
	return ok(self.names[i])
}

fn hold Box.again(i Int) &String! {
	return self.pick(i)
}

fn hold Box.via(i Int) &String! {
	s := self.pick(i)?
	return ok(s)
}

fn length_of(b Box, i Int) Int! {
	s := b.pick(i)?
	return ok(s.length())
}

fn main() Void {
	b := Box(["abc", "de"])
	print(b.pick(0))
	print(b.again(1))
	print(b.via(1))
	print(b.via(9))
	print(b.pick(7).is_error())

	match b.pick(1) {
		ok(v) => print(v)
		error(e) => print(e.message)
	}

	print(length_of(b, 0))
	print(length_of(b, 5))

	r := b.pick(0)
	print(r.get())
}
