import {TextError} from "@std/errors.ms"
import {expect_equal, expect_false, fail} from "@std/testing.ms"

type Expr:
    case Num(value: Int)
    case Add(left: Expr, right: Expr)
    case Neg(inner: Expr)

fn evaluate(expr: Expr) Int:
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
    fn equals(other: Equal) Bool:
        match other:
            Link(value): return self.value == value.value
            _: return false

impl Hashable for Link:
    fn hash() Int: return self.value

test "recursive alternatives construct match compare and clone":
    let expr = Expr.Add(left: Expr.Num(7), right: Expr.Neg(Expr.Num(2)))
    (evaluate(expr.clone()) != 5 or expr != expr.clone()) | try expect_false
    let tree = Tree[Int].Branch(left: Tree[Int].Leaf(1), right: Tree[Int].Leaf(2))
    tree | try expect_equal(
        expected: Tree[Int].Branch(
            left: Tree[Int].Leaf(1),
            right: Tree[Int].Leaf(2)
        )
    )
    let forest = Forest.More(MutualTree(value: 3, rest: Forest.Empty))

    match forest:
        More(tree):
            ((tree.value != 3 or tree.rest != Forest.Empty) | try expect_false)
        Empty: return fail("lost mutual tree")

test "recursive records clone into independent storage":
    let child = Node(value: 2, next: none)
    let root = Node(value: 1, next: some(child.clone()))
    var alias = root.clone()
    var copy = root.clone()
    alias.value = 3
    var inner = copy.next.get().clone()
    inner.value = 4
    copy.next = some(inner)
    (
        root.value != 1
        or alias.value != 3
        or copy.next.get().value != 4
        or child.value != 2
    ) | try expect_false
    copy.next = none
    root.next.is_none() | try expect_false

test "recursive structural equality checks nested and unequal fields":
    var left = Node(value: 1, next: none)
    var right = Node(value: 1, next: none)
    left.next = some(left.clone())
    right.next = some(right.clone())
    left.clone() | try expect_equal(expected: right.clone())
    var copy = left.clone()
    var inner = copy.next.get().clone()
    inner.value = 2
    copy.next = some(inner)
    (left.value != 1 or copy.value != 1 or left == copy or left != right) | try expect_false
    var a = Node(value: 1, next: none)
    let b = Node(value: 1, next: some(a.clone()))
    a.next = some(b)
    (right == a) | try expect_false

test "recursive domain hashing uses explicit implementations":
    var left = Link(value: 7, next: none)
    var right = Link(value: 7, next: none)
    left.next = some(left.clone())
    right.next = some(right.clone())
    (left != right or left.hash() != right.hash()) | try expect_false
    var values = Map[Link, Int]()
    values.add(key: left.clone(), value: 9)
    var members = Set[Link]([left.clone()])
    (values.get(right.clone()).get() != 9 or not members.contains(right.clone())) | try expect_false
    values.add(key: right.clone(), value: 10)
    members.add(right.clone())
    (
        values.length() != 1 or members.length() != 1 or values.get(
            left.clone()
        ).get() != 10
    ) | try expect_false

test "recursive defaults construct independent complete objects":
    var first = DefaultNode(value: 1)
    let second = DefaultNode(value: 2)
    first.next = some(first.clone())
    (second.next.is_some() or first.next.get().value != 1) | try expect_false

type Entry:
    name: String
    nickname: Optional[String]

type Person:
    primary: Optional[Entry]

type NestedOptional:
    case Value(value: Optional[Optional[Int]])

type NestedResult:
    value: Result[Result[Int, TextError], TextError]

type Box[T]:
    value: T

type Pair[T, U]:
    first: T
    second: U

test "finite nested generic composition constructs and extracts values":
    let person = Person(Entry(name: "Ada", nickname: some("A")))
    person.primary.get().nickname.get() | try expect_equal(expected: "A")
    let optional = NestedOptional.Value(some(some(4)))

    match optional:
        Value(value):
            try expect_equal(value.get().get(), 4)

    let result = NestedResult(ok(ok(5)))

    let inner = match result.value:
        ok(inner): inner
        error(_): return fail("unexpected outer result error")

    match inner:
        ok(value):
            try expect_equal(value, 5)
        error(_): return fail("unexpected inner result error")

    let box = Box(Box(6))
    box.value.value | try expect_equal(expected: 6)
    let pair: Pair[Optional[Int], Optional[Optional[String]]] = Pair(
        first: some(7),
        second: some(some("nested"))
    )
    (pair.first.get() != 7 or pair.second.get().get() != "nested") | try expect_false
