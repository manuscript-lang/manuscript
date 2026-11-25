// conform: tags=aliasing,diagnostics,formatter,lists,mutation,tier-core
// conform: phase=check,parse
// conform: origin=pkg/lower/list_items_test.go:22 TestListItemsCacheOnlyLoopsThatCannotReplaceItems
fn grow(values List[Int]) Void {
	values.append(0)
}

fn work(other List[Int]) Int {
	var values = [1, 2, 3, 4]
	var total = 0
}
