# `get` with a fallback returns an owned copy of the payload or of the fallback.
fn payload(o: String?) ref String:  # error: no `return` gives back part
    return o.get("none")

fn element(xs: List[String], d: String) ref String:  # error: no `return` gives back part
    return xs.get(0, default: some(d))
