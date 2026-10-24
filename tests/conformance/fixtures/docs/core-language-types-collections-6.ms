# conform: tags=closures,diagnostics,maps,strings,tier-core
# conform: phase=check
# conform: origin=documentation/core-language/types/collections.md:217
def increment_scores(scores: Map[String, Int]) -> Map[String, Int]:
    return scores.map(lambda name, score: score + 1)
