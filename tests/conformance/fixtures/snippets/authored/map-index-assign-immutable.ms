# conform: tags=maps,types,tier-core
# conform: phase=check
# conform: origin=Map and Bytes indexing
export fn main() Int:
    let scores = {"a": 1}
    scores["b"] = 2
    return scores["a"]
