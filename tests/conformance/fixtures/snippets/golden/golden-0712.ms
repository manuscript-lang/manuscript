// conform: tags=diagnostics
// conform: phase=check
fn hash[T: Hashable](value: T) Int: return value.hash()
fn f(node: Node) Int: return hash(node)
