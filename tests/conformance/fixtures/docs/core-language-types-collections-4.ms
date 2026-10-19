# conform: tags=aliasing,parser,tier-core
# conform: phase=parse
# conform: origin=documentation/core-language/types/collections.md:82
let values = [1, 2]
let alias = values
let copy = values.clone()
values.append(3)
# alias now contains [1, 2, 3]; copy still contains [1, 2].
