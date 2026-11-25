// removed: if let v = o:
// use: if value := result
// fix: if v := o {
fn main() Int {
	o Result[Int, Error] := ok(1)
	if let v = o {
		return v
	}
	return 0
}
