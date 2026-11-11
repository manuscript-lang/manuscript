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

test "method type defaults specialize receiver parameters and Self":
	exercise() | try expect_equal(0)

	box := Box(7)
	bound := box.own[String]
	values: List[String] := bound()
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
	values := default_value()
	typed: List[Value] := values
	typed.length() | try expect_equal(0)

	related := recursive_default()
	recursive: List[Value] := related
	recursive.length() | try expect_equal(0)
	read(Value(7)) | try expect_equal(7)

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

test "receiver defaults stay independent and work through generic bounds":
	alternate_receivers() | try expect_equal(0)

type ForwardFirst[T = ForwardMiddle]:
	value: T

type ForwardMiddle[U = ForwardLast]:
	value: U

type ForwardLast[V = Int]:
	value: V

fn forward_read(value: ForwardFirst) Int: value.value.value.value

test "a default may name a type declared later, through several hops":
	forward_read(ForwardFirst(ForwardMiddle(ForwardLast(5)))) | try expect_equal(5)
