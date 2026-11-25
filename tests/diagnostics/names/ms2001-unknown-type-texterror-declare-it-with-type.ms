// conform: tags=diagnostics
// conform: phase=check
fn first() Void {
	result Result[Int, TextError] := fail("empty")
}
// expect-error: MS2001 4:24 unknown type TextError; declare it with 'type TextError:' / 'enum TextError:' / 'interface TextError:', declare it as a type parameter, or import it
// expect-error: MS2001 4:38 unknown binding fail; add: import fail from "@std/test/test.ms"
// expect-fix: 1:1-1:1 "import fail from \"@std/test/test.ms\"\n"
