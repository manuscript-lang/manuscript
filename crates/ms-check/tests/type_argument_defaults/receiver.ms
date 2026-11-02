interface Reader[A: Equal]:
    fn read[B: Equal = A]() List[B]
    fn nested[B = List[A]]() List[B]

type Box[A: Equal]:
    value: A

impl Reader[A] for Box[A]:
    fn read[B: Equal = A]() List[B]: return []

    fn nested[B = List[A]]() List[B]: return []

impl Box[A]:
    fn own[B = A, C = B]() List[C]: return []

    fn copies[B = Self]() List[B]: return []

fn exercise() Int:
    let box = Box(7)
    let read = box.read()
    let nested = box.nested()
    let own = box.own()
    let copies = box.copies()
    let ints: List[Int] = read
    let lists: List[List[Int]] = nested
    let more_ints: List[Int] = own
    let boxes: List[Box[Int]] = copies
    return ints.length() + lists.length() + more_ints.length() + boxes.length()

fn from_bound[S: Reader[Int]](source: S) Int:
    let values = source.read()
    let ints: List[Int] = values
    return ints.length()

fn alternate_receivers() Int:
    let int_box = Box(7)
    let text_box = Box("value")
    let first = int_box.own()
    let second = text_box.own()
    let again = int_box.own()
    let ints: List[Int] = first
    let strings: List[String] = second
    let more_ints: List[Int] = again
    return ints.length() + strings.length() + more_ints.length() + from_bound(int_box)
