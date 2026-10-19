# conform: tags=closures,diagnostics,tier-core
# conform: phase=check
# conform: origin=documentation/core-language/functions/function-values-and-closures.md:66

fn tag_count() Int:
    let tags = ["docs"]
    let count = fn():
        return tags.length()
    tags.append("release")
    return count()
# tag_count() returns 2.
