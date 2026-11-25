// conform: tags=diagnostics
// conform: phase=check
test "legacy negative" {
	"a".replace("a", "b", -1)
}

test "required negative" {
	"a".replace_n("a", "b", -1)
}

test "bound negative" {
	replace := "a".replace_n
	replace("a", "b", -1)
}

test "empty negative" {
	"".replace_n("", "b", -1)
}

test "continues" {
	_unchanged := "a".replace_n("a", "b", 0)
}
// expect-error: MS3000 4:27 too many positional arguments; every parameter is already supplied, so remove this argument
// expect-error: MS2001 8:9 unknown or ambiguous member replace_n on String; did you mean 'replace' or 'replace_first'?
// expect-error: MS2001 12:20 unknown or ambiguous member replace_n on String; did you mean 'replace' or 'replace_first'?
// expect-error: MS2001 17:8 unknown or ambiguous member replace_n on String; did you mean 'replace' or 'replace_first'?
// expect-error: MS2001 21:23 unknown or ambiguous member replace_n on String; did you mean 'replace' or 'replace_first'?
