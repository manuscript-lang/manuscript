import expect_equal from "@std/test/test.ms"

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

test "method type defaults specialize receiver parameters and Self":
    exercise() | try expect_equal(0)

    let box = Box(7)
    let bound = box.own[String]
    let values: List[String] = bound()
    values.length() | try expect_equal(0)

interface Mark:
    fn mark() Int

type Value:
    number: Int

fn read[T: Mark = Value](value: T) Int: return value.mark()

type Holder[T: Mark = Value]:
    value: T

interface Factory:
    fn create[T: Mark = Value](value: T) Int

impl Mark for Value:
    fn mark() Int: return self.number

impl Value:
    fn read[T: Mark = Value](value: T) Int: return value.mark()

interface Relation[T]:
    fn relation(value: T) Int

impl Relation[Value] for Value:
    fn relation(value: Value) Int: return value.number

fn related[T: Relation[T] = Value](value: T) Int:
    return value.relation(value)

fn default_value[T: Mark = Value]() List[T]: return []

fn recursive_default[T: Relation[T] = Value]() List[T]: return []

test "type defaults validate local and recursive interface implementations":
    let values = default_value()
    let typed: List[Value] = values
    typed.length() | try expect_equal(0)

    let related = recursive_default()
    let recursive: List[Value] = related
    recursive.length() | try expect_equal(0)
    read(Value(7)) | try expect_equal(7)

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

test "receiver defaults stay independent and work through generic bounds":
    alternate_receivers() | try expect_equal(0)
