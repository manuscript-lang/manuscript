fn identity[T](x: T) T:
	return x

fn first[T](a: T, b: T) T:
	return a

fn second[A, B](a: A, b: B) B:
	return b

fn pick[T](a: T, b: T) T:
	return b

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
	if from_bools(false) and mixed(2) > 1.0 and from_floats() > 1.0 and from_text() == "s": return from_ints()
	return identity(0)
