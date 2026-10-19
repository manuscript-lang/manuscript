# conform: tags=closures,mutation,parser,strings,tier-core
# conform: phase=parse
# conform: origin=documentation/learn/tour.md:215

var subject = "Weekly update"
let headline = fn() String:
    return subject
subject = "Launch announcement"
# headline() returns "Weekly update".

let tags = ["docs"]
let tag_count = fn() Int:
    return tags.length()
tags.append("release")
# tag_count() returns 2.
