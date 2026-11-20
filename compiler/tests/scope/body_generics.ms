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

interface Named:
	fn name() String
	fn weight(scale: Int) Int

fn label[T: Named](value: T) String:
	return value.name()

fn heavy[T: Named](value: T, scale: Int) Int:
	return value.weight(scale)

fn missing[T: Named](value: T) Int:
	return value.nothing()

fn apply_to[A, B](value: A, transform: fn(A) B) B:
	return transform(value)

fn count_of[T](items: List[T]) Int:
	return items.len()

fn same_list[T](items: List[T]) List[T]:
	return items

fn explicit_int() Int:
	return identity[Int](3)

fn explicit_float() Float:
	return identity[Float](3)

fn explicit_first() Int:
	return pair_first[Int, String](1, "x")

fn explicit_mismatch() Int:
	return identity[Int]("x")
