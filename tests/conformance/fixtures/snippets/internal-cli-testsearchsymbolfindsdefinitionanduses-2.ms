# conform: tags=diagnostics,modules,tier-core
# conform: phase=check
# conform: origin=internal/cli/agent_test.go:59 TestSearchSymbolFindsDefinitionAndUses
from "./main.ms" import double

def quad(v: Int) -> Int:
    return double(double(v))
