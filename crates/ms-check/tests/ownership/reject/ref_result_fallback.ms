# `get` with a fallback returns an owned copy of the payload or of the fallback.
def payload(o: Optional[String]) -> ref String:  # error: no `return` gives back part
    return o.get("none")

def element(xs: List[String], d: String) -> ref String:  # error: no `return` gives back part
    return xs.get(0, default: some(d))
