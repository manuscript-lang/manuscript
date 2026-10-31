# conform: tags=diagnostics,modules,tier-core
# conform: phase=check
# conform: origin=internal/cli/agent_test.go:59 TestSearchSymbolFindsDefinitionAndUses
import double from "./main.ms"

fn quad(v: Int) Int:
    return double(double(v))
