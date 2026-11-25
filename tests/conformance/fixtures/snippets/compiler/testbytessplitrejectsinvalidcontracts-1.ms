// conform: tags=diagnostics,lists,tier-core
// conform: phase=check
// conform: origin=pkg/compiler/bytes_split_test.go:13 TestBytesSplitRejectsInvalidContracts
fn wrong(data Bytes) List[Bytes] {
	split := data.split
	return split(value: Bytes([]))
}
// expect-error: MS2001 4:15 unknown type Bytes; add: import Bytes from "@std/bytes.ms"
// expect-fix: 1:1-1:1 "import Bytes from \"@std/bytes.ms\"\n"
// expect-error: MS2001 4:27 unknown type Bytes; add: import Bytes from "@std/bytes.ms"
// expect-fix: 1:1-1:1 "import Bytes from \"@std/bytes.ms\"\n"
// expect-error: MS2001 6:25 unknown binding Bytes; add: import Bytes from "@std/bytes.ms"
// expect-fix: 1:1-1:1 "import Bytes from \"@std/bytes.ms\"\n"
