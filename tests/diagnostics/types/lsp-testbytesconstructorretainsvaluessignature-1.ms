// conform: tags=diagnostics,formatter,modules,stdlib-bytes,tier-stdlib
// conform: phase=check,parse
// conform: origin=pkg/tooling/lsp/features_test.go:266 TestBytesConstructorRetainsValuesSignature
import Bytes from "@std/bytes.ms"

fn make() Bytes {
	return
}
// expect-error: MS3000 7:5 bare return requires Void or Void!; this function returns Bytes, so write 'return <value>'
