# conform: tags=formatter,modules,parser,stdlib-bytes,stdlib-io,testing,tier-stdlib
# conform: phase=parse
# conform: origin=tests/e2e/cli_json_test.go:157 TestCLITestJSONPreservesBinaryStdout
import stdout from "@std/io.ms"
import Bytes from "@std/bytes.ms"

test "bytes":
    let data = "x".to_bytes().with_value(index: 0, value: 255)
    let _out = stdout().write_bytes(data: data)
