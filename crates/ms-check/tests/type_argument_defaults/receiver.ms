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
    box := Box(7)
    read := box.read()
    nested := box.nested()
    own := box.own()
    copies := box.copies()
    ints: List[Int] := read
    lists: List[List[Int]] := nested
    more_ints: List[Int] := own
    boxes: List[Box[Int]] := copies
    return ints.length() + lists.length() + more_ints.length() + boxes.length()

fn from_bound[S: Reader[Int]](source: S) Int:
    values := source.read()
    ints: List[Int] := values
    return ints.length()

fn alternate_receivers() Int:
    int_box := Box(7)
    text_box := Box("value")
    first := int_box.own()
    second := text_box.own()
    again := int_box.own()
    ints: List[Int] := first
    strings: List[String] := second
    more_ints: List[Int] := again
    return ints.length() + strings.length() + more_ints.length() + from_bound(int_box)
