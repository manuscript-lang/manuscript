// conform: tags=closures,diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=documentation/core-language/functions/function-values-and-closures.md:66
fn tag_count() Int {
	var tags = ["docs"]
	tags.append("release")

	count := () => {
		return tags.length()
	}
	return count()
}
// tag_count() returns 2.
// expect-exit: 0
