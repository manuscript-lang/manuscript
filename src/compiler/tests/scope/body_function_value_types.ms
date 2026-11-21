fn x(g: fn(move Int) Int, o: Int?) Int?:
	return o.map(g)

fn y(g: fn(move Int) Int?, o: Int?) Int?:
	return o.and_then(g)

fn z(o: Int?) Int!Error:
	return o.ok_or(Error("n", kind: "E"))

fn m[T, U](g: fn(move T) U, o: T?) U?:
	return o.map(g)

fn l[T, U](g: fn(T) U, xs: List[T]) List[U]:
	return xs.map(g)
