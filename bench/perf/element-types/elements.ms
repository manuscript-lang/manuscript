import monotonic from "@std/time.ms"
import (
	Deque from "@std/collections/deque.ms",
	PriorityQueue from "@std/collections/queue.ms",
)

type Event:
	id: Int
	kind: Int
	name: String
	score: Int

enum Shape:
	Circle(r: Int)
	Rect(w: Int, h: Int)
	Dot

type Pair[A, B]:
	first: A
	second: B

type Job:
	pri: Int
	id: Int

fn Job.compare(other: Job) Int:
	return self.pri - other.pri

type Pt:
	x: Int
	y: Int

fn Pt.equals(other: Pt) Bool:
	return self.x == other.x and self.y == other.y

fn Pt.hash() Int:
	return self.x * 1000003 + self.y

fn lcg(x: Int) Int:
	return (x * 1103515245 + 12345) % 2147483648

fn us(a: Int, b: Int) Int:
	return (b - a) / 1000

// 1. List of records with a String field: append, field scan.
fn list_records() Int:
	var xs: List[Event] = []
	for i in 0..1000000:
		xs.append(Event(i, i % 7, "e{i % 100}", i % 13))
	var t = 0
	for r in 0..5:
		for e in xs:
			if e.kind == 3: t += e.score + e.name.length()
	return t

// 2. List of payload enums: build, match.
fn list_enums() Int:
	var xs: List[Shape] = []
	for i in 0..2000000:
		k := i % 3
		if k == 0: xs.append(Shape.Circle(i % 10))
		else if k == 1: xs.append(Shape.Rect(i % 7, i % 5))
		else: xs.append(Shape.Dot)
	var t = 0
	for r in 0..5:
		for s in xs:
			match s:
				Circle(rad): t += 3 * rad * rad
				Rect(w, h): t += w * h
				Dot: t += 1
	return t

// 3. Map[Int, record]: insert and update in place.
fn map_records() Int:
	var m: Map[Int, Event] = {}
	var x = 1
	for i in 0..1000000:
		x = lcg(x)
		k := x % 50000
		if not m.contains(k): m[k] = Event(k, 0, "n", 0)
		m[k].score += i % 5
	var t = 0
	for e in m.values():
		t += e.score
	return t

// 4. Map[String, List[Int]]: group.
fn map_groups() Int:
	var m: Map[String, List[Int]] = {}
	var x = 1
	for i in 0..1000000:
		x = lcg(x)
		k := "k{x % 5000}"
		if not m.contains(k): m[k.clone()] = []
		m[k].append(i)
	var t = 0
	for e in m.entries():
		t += e.value.length()
	return t

// 5. Optional[record]: return an optional record from a lookup, 10M times.
fn find(xs: List[Event], i: Int) Event?:
	if i % 4 == 0: return none
	return xs[i % xs.length()].clone()

fn optional_records() Int:
	var xs: List[Event] = []
	for i in 0..1000:
		xs.append(Event(i, i % 7, "e", i % 13))
	var t = 0
	for i in 0..5000000:
		e := find(xs, i)
		if e.is_some(): t += e.get().score
	return t

// 6. Deque of records.
fn deque_records() Int:
	var q = Deque[Job]()
	var t = 0
	for i in 0..3000000:
		q.push_back(Job(i % 100, i))
		if i % 3 == 2:
			j := q.pop_front()
			if j.is_some(): t += j.get().pri
	return t

// 7. PriorityQueue of records.
fn pq_records() Int:
	var pq = PriorityQueue[Job]()
	var x = 1
	var t = 0
	for i in 0..1000000:
		x = lcg(x)
		pq.enqueue(Job(x % 100000, i))
		if i % 3 == 2:
			j := pq.dequeue()
			if j.is_some(): t += j.get().pri
	return t

// 8. Generic Pair[Int, String] list and a generic helper.
fn first_of[A: Clonable, B](xs: List[Pair[A, B]]) List[A]:
	var out: List[A] = []
	for p in xs:
		out.append(p.first.clone())
	return out

fn generic_pairs() Int:
	var xs: List[Pair[Int, String]] = []
	for i in 0..1000000:
		xs.append(Pair[Int, String](i, "v{i % 10}"))
	var t = 0
	for r in 0..5:
		for a in first_of(xs):
			t += a % 10
	return t

// 9. Result of a record in a hot call.
fn make(i: Int) Event!:
	if i % 10 == 0: return error(Error("bad", kind: "EINVAL"))
	return ok(Event(i, i % 7, "r", i % 13))

fn results() Int:
	var t = 0
	for i in 0..5000000:
		r := make(i)
		if r.is_ok(): t += r.get().score
	return t

// 10. Set of record keys.
fn set_records() Int:
	var s = Set[Pt]()
	var x = 1
	var t = 0
	for i in 0..1000000:
		x = lcg(x)
		p := Pt(x % 1000, (x / 1000) % 1000)
		if s.contains(p): t += 1
		else: s.add(p)
	return t + s.length()

// 11. Sorting records by a comparator.
fn sort_records() Int:
	var xs: List[Event] = []
	var x = 1
	for i in 0..500000:
		x = lcg(x)
		xs.append(Event(i, x % 1000, "s", i % 13))
	ys := xs.sorted(fn a, b: a.kind - b.kind)
	return ys[0].kind + ys[ys.length() - 1].kind + ys[1000].id % 7

fn main() Unit:
	t0 := monotonic().tick
	a := list_records()
	t1 := monotonic().tick
	print("list-records {us(t0, t1)} {a}")
	b := list_enums()
	t2 := monotonic().tick
	print("list-enums {us(t1, t2)} {b}")
	c := map_records()
	t3 := monotonic().tick
	print("map-records {us(t2, t3)} {c}")
	d := map_groups()
	t4 := monotonic().tick
	print("map-groups {us(t3, t4)} {d}")
	e := optional_records()
	t5 := monotonic().tick
	print("optional-records {us(t4, t5)} {e}")
	f := deque_records()
	t6 := monotonic().tick
	print("deque-records {us(t5, t6)} {f}")
	g := pq_records()
	t7 := monotonic().tick
	print("pq-records {us(t6, t7)} {g}")
	h := generic_pairs()
	t8 := monotonic().tick
	print("generic-pairs {us(t7, t8)} {h}")
	i := results()
	t9 := monotonic().tick
	print("result-records {us(t8, t9)} {i}")
	j := set_records()
	t10 := monotonic().tick
	print("set-records {us(t9, t10)} {j}")
	k := sort_records()
	t11 := monotonic().tick
	print("sort-records {us(t10, t11)} {k}")
