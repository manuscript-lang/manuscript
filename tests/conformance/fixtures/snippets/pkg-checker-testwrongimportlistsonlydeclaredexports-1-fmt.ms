# conform: tags=alternatives,formatter,parser,records,strings,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/hints_test.go:108 TestWrongImportListsOnlyDeclaredExports
export type MoneyError:
    case Invalid

export def parse_cents() -> Int: 0

export def format_cents() -> String: "0"
