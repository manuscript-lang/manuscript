// conform: tags=testing,tier-core
// conform: phase=check
export fn main() Int {
	items := [2, 1]
	items.sort()
	return items.length()
}
// expect-error: MS3060 5:5 cannot change `items`: `items` is an immutable binding, immutable including its contents; declare it `var items` to change it
// expect-fix: 4:5-4:13 "var items ="
