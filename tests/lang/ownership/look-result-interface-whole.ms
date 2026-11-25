// conform: tags=ownership,interfaces
// conform: phase=run
type Box {
	name String
}

type Whole {
	held String!
}

interface Look {
	hold fn pick() &String!
}

fn hold Box.pick() &String! {
	return ok(self.name)
}

fn hold Whole.pick() &String! {
	return self.held
}

fn show(look Look) Void! {
	print(look.pick()?)
}

fn main() Void {
	print(show(Box("box")).is_error().to_string())
	print(show(Whole(ok("whole"))).is_error().to_string())
	print(show(Whole(error(Error("bad")))).is_error().to_string())
}
