interface Sink:
    fn put(s: String, var into: List[String]) Unit

type Lines:
    unused: Bool = false

fn Lines.put(s: String, into: List[String]) Unit:
    return unit

fn view() Sink:
    return Lines()  // error: expected Sink, found Lines (in the return value); Lines does not satisfy Sink by its own methods (put must be declared as fn put(s: String, var into: List[String]) Unit); declare each operation as a method of Lines with the interface's exact signature
