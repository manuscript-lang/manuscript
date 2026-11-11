// conform: tags=diagnostics,lists,strings,tier-core
// conform: phase=check
// conform: origin=documentation/core-language/modules/declarations.md:32
export MAX_ITEMS := 100
NAMES: List[String] := ["Ada", "Grace"]
LIMIT := MAX_ITEMS * 2

fn is_full(count: Int) Bool:
    return count >= LIMIT
