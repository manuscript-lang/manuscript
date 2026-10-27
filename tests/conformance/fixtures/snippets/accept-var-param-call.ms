# conform: tags=mutation,functions,tier-core
# conform: phase=check
# conform: origin=ms-check/tests/messages.rs
def child(var c: List[String]) -> Int:
    c.append("a")
    return 1

export def main() -> Int:
    var c = ["x"]
    return child(var c) - 1
