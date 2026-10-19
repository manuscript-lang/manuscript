# conform: tags=formatter,modules,parser,tier-core
# conform: phase=parse
# conform: origin=internal/cli/agent_test.go:59 TestSearchSymbolFindsDefinitionAndUses
import {double} from "./main.ms"
fn quad(v: Int) Int:
    return double(double(v))
