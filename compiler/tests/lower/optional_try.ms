type Num:
	value: Int
	next: Int

fn digits(at: Int) Num?:
	if at > 3: return none
	return Num(value: at, next: at + 1)

fn twice(at: Int) Num?:
	a := digits(at)?
	b := digits(a.next)?
	return Num(value: a.value + b.value, next: b.next)

fn main() Int:
	if twice(1).is_some(): return 0
	return 1
