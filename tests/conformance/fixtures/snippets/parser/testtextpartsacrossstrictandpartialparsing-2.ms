// conform: tags=diagnostics,strings,tier-core
// conform: phase=check
// conform: origin=pkg/parser/text_test.go:22 TestTextPartsAcrossStrictAndPartialParsing
// prefix
fn value() String {
	return
}
// expect-error: MS3000 6:5 bare return requires Void or Void!; this function returns String, so write 'return <value>'
