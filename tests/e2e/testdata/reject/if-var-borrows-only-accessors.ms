export fn main() Int:
    var o: List[String]? = some(["a"])
    var n = 0
    if var l = o:
        l.append("q")
    if let k = o:
        n += k.length()
    return n
