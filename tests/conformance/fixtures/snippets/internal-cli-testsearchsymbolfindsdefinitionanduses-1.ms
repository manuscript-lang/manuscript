# conform: tags=functions,tier-core
# conform: phase=run
# conform: origin=internal/cli/agent_test.go:58 TestSearchSymbolFindsDefinitionAndUses
# Doubles a number.
export fn double(value: Int) Int:
    return value * 2

export fn main() Int:
    return double(4) - 8
