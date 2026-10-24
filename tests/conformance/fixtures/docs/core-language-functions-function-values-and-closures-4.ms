# conform: tags=closures,diagnostics,tier-core
# conform: phase=check
# conform: origin=documentation/core-language/functions/function-values-and-closures.md:66
def tag_count() -> Int:
    var tags = ["docs"]
    tags.append("release")

    let count = lambda:
        return tags.length()
    return count()
# tag_count() returns 2.
