// conform: tags=diagnostics
// conform: phase=check
export fn main() Int {
	values := [1, 2]
	values.insert(3, 9)
	return values.length()
}
// expect-error: MS3060 5:5 cannot change `values`: `values` is an immutable binding, immutable including its contents; declare it `var values` to change it
// expect-fix: 4:5-4:14 "var values ="
