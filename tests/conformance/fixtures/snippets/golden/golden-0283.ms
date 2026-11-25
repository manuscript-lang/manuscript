// conform: tags=diagnostics
// conform: phase=check
enum Choice[T] {
	Found(value T)
	Missing
}

fn f(c Choice[Int]) Int {
	match c {
		Choice[String].Found(v) => return 1
		Choice[String].Missing => return 0
	}
}
// expect-error: MS3000 10:9 pattern belongs to a different alternative; qualify arms with the matched type, Choice.<case>
// expect-error: MS3000 11:9 pattern belongs to a different alternative; qualify arms with the matched type, Choice.<case>
