// conform: tags=diagnostics,formatter,records,strings,tier-core
// conform: phase=check,parse
// conform: origin=pkg/parser/partial_test.go:24 FuzzParsePartial
type Box {
	value String
}
// expect-exit: 0
