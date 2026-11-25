// conform: tags=maps,types,tier-core
// conform: phase=check
// conform: origin=Map and Bytes indexing
export fn main() Int {
	scores := {"a": 1}
	scores["b"] = 2
	return scores["a"]
}
// expect-error: MS3060 6:5 cannot change `scores`: `scores` is an immutable binding, immutable including its contents; declare it `var scores` to change it
// expect-fix: 5:5-5:14 "var scores ="
