# conform: tags=formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/lsp/query_test.go:45 TestSearchSymbolsRanksExactBeforePrefixBeforeSubstring
fn parse_all() Int:
    return 1

fn reparse() Int:
    return 2

fn parse() Int:
    return 3

export fn main() Int:
    return parse()
