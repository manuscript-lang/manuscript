// Interfaces, closures and generics: dynamic dispatch over a mixed list, a chain of
// closures, a generic container.
interface Shape:
	fn area() Int
	fn grow(by: Int) Int

type Sq:
	s: Int

type Rect:
	w: Int
	h: Int

type Tri:
	b: Int
	h: Int

fn Sq.area() Int:
	return self.s * self.s

fn Sq.grow(by: Int) Int:
	return (self.s + by) * (self.s + by)

fn Rect.area() Int:
	return self.w * self.h

fn Rect.grow(by: Int) Int:
	return (self.w + by) * (self.h + by)

fn Tri.area() Int:
	return self.b * self.h / 2

fn Tri.grow(by: Int) Int:
	return (self.b + by) * (self.h + by) / 2

fn shapes(n: Int) Int:
	var xs: List[Shape] = []

	for i in 0..n:
		k := i % 3

		if k == 0: xs.append(Sq(i % 10 + 1))
		else if k == 1: xs.append(Rect(i % 7 + 1, i % 5 + 1))
		else: xs.append(Tri(i % 9 + 1, i % 4 + 1))

	var total = 0
	for pass in 0..20:
		for s in xs:
			total += s.area() + s.grow(pass)
	return total

fn closures(n: Int) Int:
	offset := 3
	steps: List[fn(Int) Int] := [
		fn(x: Int) Int: return x + offset,
		fn(x: Int) Int: return x * 2,
		fn(x: Int) Int: return x - 1,
		fn(x: Int) Int: return x % 1000003
	]
	var acc = 1
	for i in 0..n:
		for f in steps:
			acc = f(acc + i)
	return acc

type Stack[T]:
	items: List[T] = []

fn var Stack[T].push(v: T) Unit:
	self.items.append(v)

fn var Stack[T].pop() T?:
	return self.items.pop()

fn fold_with[T](xs: List[T], init: Int, step: fn(Int, T) Int) Int:
	var acc = init
	for x in xs:
		acc = step(acc, x)
	return acc

fn generics(n: Int) Int:
	var s = Stack[Int]()
	var t = 0

	for i in 0..n:
		s.push(i % 1000)

		if i % 3 == 2:
			v := s.pop()
			if v.is_some(): t += v.get()

	return t + fold_with(s.items, 0, fn(a: Int, x: Int) Int: return a + x * 2)

fn main() Unit:
	print("shapes {shapes(1000000)}")
	print("closures {closures(15000000)}")
	print("generics {generics(20000000)}")
