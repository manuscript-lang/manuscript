# conform: tags=formatter,parser,tier-core
# conform: phase=parse
# conform: origin=internal/cli/agent_test.go:58 TestSearchSymbolFindsDefinitionAndUses
# Doubles a number.
export def double(value: Int) -> Int:
    return value * 2

export def main() -> Int:
    return double(4) - 8
