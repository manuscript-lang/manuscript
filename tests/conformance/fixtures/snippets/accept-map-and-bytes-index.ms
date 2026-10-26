# conform: tags=maps,types,tier-core
# conform: phase=check
# conform: origin=ms-check/tests/messages.rs
export def main() -> Int:
    var m = Map[String, Int]()
    m["a"] = 1
    let b = "x".to_bytes()
    return m["a"] + b[0]
