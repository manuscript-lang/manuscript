# conform: tags=control-flow,faults,interpolation,parser,sets,strings,tier-core
# conform: phase=parse
# conform: origin=documentation/learn/tour.md:49
let tags = ["docs", "release"]
tags.append("featured")
let original = tags.clone()
tags.append("news")
# original still has three tags.

let visits = {"/help": 12}
visits.add("/tour", 4)
let subscribers = Set[String]()
subscribers.add("sam@example.com")

if let count = visits.get("/help"):
    let label = "{count} visits"
else:
    let label = "No visits yet"
