// A program that spends its compile time in the standard-library YAML parser.
// `tools/llvm-direct-check.ms` reports the size and build time of its LLVM IR with and
// without direct emission.
import parse, stringify from "@std/data/yaml.ms"

fn main() Int:
	text := "name: demo\nitems:\n  - 1\n  - two\n  - \{three: 3, four: [4, 4]\}\nflag: true\n"

	if value := parse(text):
		print(stringify(value).get(""))
		return 0

	return 1
