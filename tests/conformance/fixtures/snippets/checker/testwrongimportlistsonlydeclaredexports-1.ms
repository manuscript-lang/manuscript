// conform: tags=alternatives,diagnostics,formatter,records,strings,tier-core
// conform: phase=check,parse
// conform: origin=pkg/checker/hints_test.go:108 TestWrongImportListsOnlyDeclaredExports
export enum MoneyError {
	Invalid
}

export fn parse_cents() Int => 0

export fn format_cents() String => "0"
// expect-exit: 0
