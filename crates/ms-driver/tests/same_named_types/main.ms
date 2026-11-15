import (
	T from "./one.ms",
	make from "./two.ms",
)

fn main() Unit:
	x: T := make()
	print(x.n)
