// conform: tags=closures,formatter,parser,tier-core
// conform: phase=parse
// conform: origin=pkg/parser/positional_arguments_test.go:12 TestMixedArgumentsStrictAndPartial
fn run() Int {
	return select[Int](1, last: 3, value => value + 1)
}
