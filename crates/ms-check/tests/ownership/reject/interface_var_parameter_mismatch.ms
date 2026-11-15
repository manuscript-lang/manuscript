interface Sink:
    fn put(s: String, var into: List[String]) Void

type Lines:
    unused: Bool = false

fn Lines.put(s: String, into: List[String]) Void:
    return unit

fn view() Sink:
    return Lines()  // error: expected Sink, found Lines (in the return value); Lines does not satisfy Sink by its own methods (put must be declared as fn put(s: String, var into: List[String]) Void); declare each operation as a method of Lines with the interface's exact signature
