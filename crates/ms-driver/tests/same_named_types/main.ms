import (
	T from "./one.ms",
	make from "./two.ms",
)

fn main() Void:
	x: T := make()
	print(x.n)
