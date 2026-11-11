// conform: tags=diagnostics
// conform: phase=check
fn transform(value: Int, key: String) Int: value
fn wrong(values: Map[String, Int]) Map[String, Int]: values.map(transform)