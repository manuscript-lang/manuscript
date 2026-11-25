// conform: tags=diagnostics
// conform: phase=check
test "new set" {
	[1].set(1, 2)
}

test "bound set" {
	set := [1].set
	set(-2, 2)
}

test "new remove" {
	[1].remove(1)
}

test "bound remove" {
	remove := [1].remove
	remove(-2)
}

test "empty set" {
	items List[Int] := []
	items.set(0, 2)
}

test "empty remove" {
	items List[Int] := []
	items.remove(0)
}

test "old replace" {
	"a".replace("a", "b", -1)
}

test "new replace" {
	"a".replace_first("a", "b", -1)
}

test "bound replace" {
	first := "a".replace_first
	first("a", "b", -1)
}

test "continues" {
	result := [1].set(0, 2).remove(0)
}
// expect-error: MS3000 32:27 too many positional arguments; every parameter is already supplied, so remove this argument
// expect-error: MS3000 36:33 too many positional arguments; every parameter is already supplied, so remove this argument
// expect-error: MS3000 41:21 too many positional arguments; every parameter is already supplied, so remove this argument
// expect-error: MS2001 45:29 unknown or ambiguous member remove on Void; this type has no fields or operations
