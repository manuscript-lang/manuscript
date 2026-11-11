// conform: tags=diagnostics
// conform: phase=check
fn check(value: Int, key: String) Bool: true
fn wrong(value: Map[String, Int]) Bool: value.every(check)