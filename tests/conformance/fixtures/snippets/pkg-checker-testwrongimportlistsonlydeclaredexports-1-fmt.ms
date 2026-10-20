# conform: tags=alternatives,formatter,parser,records,strings,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/hints_test.go:108 TestWrongImportListsOnlyDeclaredExports
export type MoneyError:
    case Invalid
export fn parse_cents() Int: 0
export fn format_cents() String: "0"
