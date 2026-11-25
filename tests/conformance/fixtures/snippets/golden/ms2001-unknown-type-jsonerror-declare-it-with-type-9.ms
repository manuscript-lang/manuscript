// conform: tags=diagnostics
// conform: phase=check
type Request {
	model String
}

fn f(text String) Result[Request, JsonError] {
	return parse(text)
}
// expect-error: MS2001 7:35 unknown type JsonError; declare it with 'type JsonError:' / 'enum JsonError:' / 'interface JsonError:', declare it as a type parameter, or import it
// expect-error: MS2001 8:12 unknown binding parse; add: import parse from "@std/data/csv.ms"
// expect-fix: 1:1-1:1 "import parse from \"@std/data/csv.ms\"\n"
