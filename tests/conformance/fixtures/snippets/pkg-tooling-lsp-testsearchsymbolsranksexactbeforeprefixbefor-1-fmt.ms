# conform: tags=formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/lsp/query_test.go:45 TestSearchSymbolsRanksExactBeforePrefixBeforeSubstring
def parse_all() -> Int:
    return 1

def reparse() -> Int:
    return 2

def parse() -> Int:
    return 3

export def main() -> Int:
    return parse()
