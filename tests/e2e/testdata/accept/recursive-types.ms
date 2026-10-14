import {Map, Set} from "@std/collections.ms"
import panic from "@std/faults.ms"
import {Equal, Hashable} from "@std/equality.ms"

type Expr:
    case Num(value: Int)
    case Add(left: Expr, right: Expr)
    case Neg(inner: Expr)

fn evaluate(expr: Expr) -> Int:
    match expr:
        Num(value): return value
        Add(left, right): return evaluate(left) + evaluate(right)
        Neg(inner): return -evaluate(inner)

type Tree[T]:
    case Leaf(value: T)
    case Branch(left: Tree[T], right: Tree[T])

type Forest:
    case Empty
    case More(tree: MutualTree)

type MutualTree:
    value: Int
    rest: Forest

type Node:
    value: Int
    next: Optional[Node]

type DefaultNode:
    value: Int
    next: Optional[DefaultNode] = none

type Link:
    value: Int
    next: Optional[Link]

impl Equal for Link:
    fn equals(other: Equal) -> Bool:
        match other:
            Link(value): return self.value == value.value
            _: return false

impl Hashable for Link:
    fn hash() -> Int: return self.value

test "recursive alternatives construct match compare and clone":
    let expr = Expr.Add(left: Expr.Num(7), right: Expr.Neg(Expr.Num(2)))

    if evaluate(expr) != 5 or expr != expr.clone():
        panic("recursive expression failed")

    let tree = Tree[Int].Branch(left: Tree[Int].Leaf(1), right: Tree[Int].Leaf(2))

    if tree != Tree[Int].Branch(left: Tree[Int].Leaf(1), right: Tree[Int].Leaf(2)):
        panic("generic tree equality failed")

    let forest = Forest.More(MutualTree(value: 3, rest: Forest.Empty))

    match forest:
        More(tree):
            if tree.value != 3 or tree.rest != Forest.Empty:
                panic("mutual tree payload failed")
        Empty: panic("lost mutual tree")

test "recursive records retain aliases and clone only outer storage":
    let child = Node(value: 2, next: none)
    let root = Node(value: 1, next: child)
    let alias = root
    let copy = root.clone()
    alias.value = 3
    copy.next.unwrap().value = 4

    if (root.value != 3 or copy.value != 1 or child.value != 4):
        panic("recursive alias or shallow clone failed")

    copy.next = none

    if root.next.is_none():
        panic("clone shared its outer fields")

test "recursive structural equality terminates and checks unequal fields":
    let left = Node(value: 1, next: none)
    let right = Node(value: 1, next: none)
    left.next = some(left)
    right.next = some(right)

    if left != right:
        panic("equivalent cycles differ")

    let copy = left.clone()
    copy.next.unwrap().value = 2

    if (left.value != 2 or copy.value != 1 or left == right):
        panic("cyclic clone or unequal cycle failed")

    let a = Node(value: 1, next: none)
    let b = Node(value: 1, next: a)
    a.next = some(b)

    if right != a:
        panic("equivalent one-node and two-node cycles differ")

test "recursive domain hashing uses explicit implementations":
    let left = Link(value: 7, next: none)
    let right = Link(value: 7, next: none)
    left.next = some(left)
    right.next = some(right)

    if left != right or left.hash() != right.hash():
        panic("explicit cyclic identity hashing failed")

    let values = Map[Link, Int]().add(key: left, value: 9)
    let members = Set[Link]().add(left)

    if values.get(right).unwrap() != 9 or not members.contains(right):
        panic("explicit recursive key lookup failed")

    values.add(key: right, value: 10)
    members.add(right)

    if (
        values.length() != 1
        or members.length() != 1
        or values.get(left).unwrap() != 10
    ):
        panic("equivalent recursive keys were not deduplicated")

test "recursive defaults construct independent complete objects":
    let first = DefaultNode(value: 1)
    let second = DefaultNode(value: 2)
    first.next = some(first)

    if second.next.is_some() or first.next.unwrap().value != 1:
        panic("recursive default initialization failed")

type Entry:
    name: String
    nickname: Optional[String]

type Person:
    primary: Optional[Entry]

type NestedOptional:
    case Value(value: Optional[Optional[Int]])

type NestedResult:
    value: Result[Result[Int, String], String]

type Box[T]:
    value: T

type Pair[T, U]:
    first: T
    second: U

test "finite nested generic composition constructs and extracts values":
    let person = Person(Entry(name: "Ada", nickname: some("A")))

    if person.primary.unwrap().nickname.unwrap() != "A":
        panic("composed optional entry failed")

    let optional = NestedOptional.Value(some(some(4)))

    match optional:
        Value(value):
            if value.unwrap().unwrap() != 4:
                panic("nested optional payload failed")

    let result = NestedResult(ok(ok(5)))

    let inner = match result.value:
        ok(inner): inner
        error(_): panic("unexpected outer result error")

    match inner:
        ok(value):
            if value != 5: panic("nested result value failed")
        error(_): panic("unexpected inner result error")

    let box = Box(Box(6))

    if box.value.value != 6:
        panic("nested box failed")

    let pair: Pair[Optional[Int], Optional[Optional[String]]] = Pair(
        first: some(7),
        second: some(some("nested"))
    )

    if pair.first.unwrap() != 7 or pair.second.unwrap().unwrap() != "nested":
        panic("nested optional generic pair failed")
