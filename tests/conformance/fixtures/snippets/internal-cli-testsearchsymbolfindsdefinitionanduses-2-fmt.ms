# conform: tags=formatter,modules,parser,tier-core
# conform: phase=parse
# conform: origin=internal/cli/agent_test.go:59 TestSearchSymbolFindsDefinitionAndUses
from "./main.ms" import double

def quad(v: Int) -> Int:
    return double(double(v))
