// conform: tags=closures,formatter,maps,parser,strings,tier-core
// conform: phase=parse
// conform: origin=documentation/core-language/types/collections.md:217
fn increment_scores(scores Map[String, Int]) Map[String, Int]:
    return scores.map((name, score) => score + 1)
