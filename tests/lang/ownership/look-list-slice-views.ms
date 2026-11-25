// conform: tags=ownership,lists
// conform: phase=run
fn main() Void! {
	xs := ["a", "b", "c"]
	ys := xs.slice(0, 2)?
	print(ys.length().to_string())
	print(ys[1])
	zs := xs.slice(1, 3)?.clone()
	print(zs.length().to_string())
	print(xs.slice(2, 9).is_error().to_string())
}
