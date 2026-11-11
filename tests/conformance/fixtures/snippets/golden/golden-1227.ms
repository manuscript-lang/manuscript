// conform: tags=diagnostics
// conform: phase=check
// max items
export MAX_ITEMS := 100
NAMES: List[String] := ["a"]
LIMIT := MAX_ITEMS * 2

fn is_full(count: Int) Bool:
    return count >= LIMIT
fn names() Int:
    return NAMES.length()
