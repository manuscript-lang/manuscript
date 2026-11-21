type Box[T]:
	value: T
	tag: Int

type Pair[A, B]:
	first: A
	second: B

fn unbox(b: Box[Int]) Int:
	return b.value + b.tag

fn make(n: Int) Box[Int]:
	return Box(value: n, tag: 2)

fn swap_sum(p: Pair[Int, Float]) Float:
	return p.second

fn label(b: Box[String]) String:
	return b.value

fn main() Int:
	b := make(3)
	p := Pair(first: 1, second: 2.5)
	if swap_sum(p) > 1.0: return unbox(b)
	return 0
