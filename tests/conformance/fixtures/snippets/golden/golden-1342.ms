// conform: tags=diagnostics
// conform: phase=check
type Box[T] {
	value T
}

fn use[T](value Box[T]?) T {
	match value {
		box => return Box.value
		null => return panic(message: "empty")
	}
}
// expect-error: MS2001 9:27 Box has no member value; a type name is followed only by an enum case
// expect-error: MS2001 10:24 unknown binding panic; add: import panic from "@std/core.ms"
// expect-fix: 1:1-1:1 "import panic from \"@std/core.ms\"\n"
