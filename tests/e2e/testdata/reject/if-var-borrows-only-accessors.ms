export fn main() Int:
    var o: List[String]? = ["a"]
    var n = 0
    if var l = o:
        l.append("q")
    if k := o:
        n += k.length()
    return n
