# conform: tags=alternatives,diagnostics,records,strings,tier-core
# conform: phase=check
# conform: origin=pkg/checker/hints_test.go:108 TestWrongImportListsOnlyDeclaredExports
export type MoneyError:
    case Invalid
export fn parse_cents() Int: 0
export fn format_cents() String: "0"
