type Point:
	x: Int
	y: Int

fn identity[T](x: T) T:
	return x

fn first[T](a: T, b: T) T:
	return a

fn second[A, B](a: A, b: B) B:
	return b

fn pick[T](a: T, b: T) T:
	return b

fn wrap[T](a: T) T:
	return identity(a)

fn wrap_pair[T](a: T, b: T) T:
	return first(a, b)

fn from_nested() Float:
	return wrap(wrap_pair(1.5, 2.5)) + wrap(0.5)

fn from_records() Int:
	p := identity(Point(x: 1, y: 2))
	q := pick(p, Point(x: 3, y: 4))
	return q.y

fn from_ints() Int:
	a := identity(3)
	b := first(4, 5)
	return a + b + identity(a)

fn from_floats() Float:
	a := identity(1.5)
	return first(a, 2.5)

fn mixed(n: Int) Float:
	return second(n, 2.5)

fn from_bools(flag: Bool) Bool:
	return pick(flag, true)

fn from_text() String:
	return identity("s")

fn main() Int:
	if (
		from_records() > 0
		and from_nested() > 0.0
		and from_bools(false)
		and mixed(2) > 1.0
		and from_floats() > 1.0
		and from_text() == "s"
	): return from_ints()
	return identity(0)
