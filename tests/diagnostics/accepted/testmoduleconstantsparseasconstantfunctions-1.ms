// conform: tags=diagnostics,formatter,lists,strings,tier-core
// conform: phase=check,parse
// conform: origin=pkg/parser/constants_test.go:10 TestModuleConstantsParseAsConstantFunctions
export LIMIT := 10
NAMES List[String] := ["a"]
// expect-exit: 0
