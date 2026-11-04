interface Sink:
    fn put(s: String, var into: List[String]) Unit

type Lines:
    unused: Bool = false

impl Sink for Lines:
    fn put(s: String, into: List[String]) Unit:  // error: signature does not match contract
        return unit
