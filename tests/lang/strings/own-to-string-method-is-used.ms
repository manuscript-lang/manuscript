// conform: tags=strings,interpolation,records,tier-core
// conform: phase=run
type Money {
	cents Int
}

fn Money.to_string() String {
	return f"{self.cents / 100}.{self.cents % 100}"
}

type Plain {
	n Int
}

type Box[T] {
	value T
}

fn Box[T].to_string() String {
	return "box"
}

type Wallet {
	owner String
	balance Money
	history List[Money]
	note Money?
}

enum Shape {
	Dot
	Line(len Int)
}

fn Shape.to_string() String {
	return "shape"
}

fn show[V](v V) String {
	return v.to_string()
}

fn main() Void {
	m := Money(1250)
	print(m.to_string())

	convert fn() String := m.to_string
	print(convert())
	print(f"{m}")
	print(m)
	print(show(m))
	print(Dot.to_string())
	print(f"{Line(4)}")
	print(Plain(2))
	print(f"{Plain(3)}")
	print(Box(1).to_string())
	print(f"{Box("x")}")
	print([Box(1), Box(2)])
	print([m.clone()])
	print({"a": m.clone()})

	maybe Money? := m.clone()
	print(maybe)
	print(f"{[m.clone(), Money(5)]}")
	print(Wallet("ada", m.clone(), [Money(5)], null))
}
