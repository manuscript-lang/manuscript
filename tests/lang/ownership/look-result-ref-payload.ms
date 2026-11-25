// conform: tags=ownership,try-result
// conform: phase=run
type Box {
	names List[String]
}

fn hold Box.pick(i Int) &String! {
	if i >= self.names.length() { return error(Error("out of range")) }
	return ok(self.names[i])
}

fn main() Void {
	b := Box(["a", "b"])
	x := b.pick(1)
	print(x)

	y := b.pick(5)
	print(y.is_error())
}
// expect-exit: 0
// expect-stdout: ok(b)
// expect-stdout: true
