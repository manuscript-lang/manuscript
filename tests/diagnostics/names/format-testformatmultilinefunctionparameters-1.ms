// conform: tags=diagnostics,formatter,interpolation,lists,match,strings,tier-core
// conform: phase=check,parse
// conform: origin=pkg/tooling/format/format_test.go:161 TestFormatMultilineFunctionParameters
export fn render(
	arguments List[String],  // arguments
	output WriteStream,
) Int {
	message := f"Arguments: {arguments.join(",")}\n"

	match output.write(data: message) {
		ok(_) => {
			return 0
		}
		error(_) => {
			return 1
		}
	}
}
// expect-error: MS2001 6:12 unknown type WriteStream; add: import WriteStream from "@std/io/io.ms"
// expect-fix: 1:1-1:1 "import WriteStream from \"@std/io/io.ms\"\n"
