// Calls of generic functions the C body checker claims.
fn identity[T](value: T) T:
	return value

fn larger[T: Comparable](a: T, b: T) T:
	if a > b: return a
	return b

fn pair_first[A, B](a: A, b: B) A:
	return a

fn int_identity() Int:
	return identity(3)

fn string_identity() String:
	return identity("hi")

fn float_larger(x: Float) Float:
	return larger(x, 2.5)

fn first_of_mixed() Int:
	return pair_first(7, "x")

fn through_binding() Bool:
	flag := identity(true)
	return flag

fn conflicting() Int:
	return larger(1, 2.5)

fn pass_through[T](value: T) T:
	return value

fn through_call[T](value: T) T:
	return identity(value)

fn first_of[A, B](a: A, b: B) A:
	return a

fn rebind[T](value: T) T:
	copy := value
	return copy
