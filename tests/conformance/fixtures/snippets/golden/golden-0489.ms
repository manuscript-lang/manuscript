// conform: tags=diagnostics
// conform: phase=check
fn first() Void {
	value fn(String) Result[Int, TextError] := fail
}
// expect-error: MS2001 4:34 unknown type TextError; declare it with 'type TextError:' / 'enum TextError:' / 'interface TextError:', declare it as a type parameter, or import it
// expect-error: MS2001 4:48 unknown binding fail; add: import fail from "@std/test/test.ms"
// expect-fix: 1:1-1:1 "import fail from \"@std/test/test.ms\"\n"
