// conform: tags=closures,diagnostics,formatter,maps,strings,tier-core
// conform: phase=check,parse
// conform: origin=documentation/core-language/types/collections.md:217
fn increment_scores(scores Map[String, Int]) Map[String, Int] {
	return scores.map((name, score) => score + 1)
}
// expect-exit: 0
