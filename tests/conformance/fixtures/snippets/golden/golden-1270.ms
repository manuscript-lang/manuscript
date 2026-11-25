// conform: tags=diagnostics
// conform: phase=check
fn read(values List[Int], index Int) Int {
	result := match values.take(index).first() {
		number => {
			doubled := number * 2
			doubled
		}
		null => 0
	}

	return result
}
// expect-exit: 0
