// conform: tags=diagnostics
// conform: phase=check
fn f[T](text String) Result[T, JsonError] {
	return parse[T](text)
}
// expect-error: MS2001 3:32 unknown type JsonError; declare it with 'type JsonError:' / 'enum JsonError:' / 'interface JsonError:', declare it as a type parameter, or import it
// expect-error: MS2001 4:12 unknown binding parse; add: import parse from "@std/data/csv.ms"
// expect-fix: 1:1-1:1 "import parse from \"@std/data/csv.ms\"\n"
