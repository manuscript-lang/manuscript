// conform: tags=closures,diagnostics,formatter,lists,strings,tier-core
// conform: phase=check,parse
// conform: origin=documentation/core-language/functions/function-values-and-closures.md:99
fn names() List[String] {
	return [1, 2].map(value => value.to_string())
}
// expect-exit: 0
