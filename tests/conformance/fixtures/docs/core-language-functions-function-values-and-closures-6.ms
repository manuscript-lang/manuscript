// conform: tags=closures,diagnostics,lists,strings,tier-core
// conform: phase=check
// conform: origin=documentation/core-language/functions/function-values-and-closures.md:99
fn names() List[String] {
	return [1, 2].map(value => value.to_string())
}
