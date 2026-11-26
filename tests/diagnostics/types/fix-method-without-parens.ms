// conform: tags=diagnostics,tier-core
// conform: phase=check
fn count(items List[Int]) Int {
	if items.length > 0 {
		return items.length
	}
	return 0
}
// expect-error: MS3001 4:21 operator operands require the same independently known type, found fn() Int > Int; this is a method, not a property; call it with parentheses, as in `xs.length()`
// expect-fix: 4:8-4:20 "items.length()"
// expect-error: MS3001 5:22 expected Int, found fn() Int (in the return value); this is a method, not a property; call it with parentheses to get its Int result, as in `xs.length()`
// expect-fix: 5:16-5:28 "items.length()"
