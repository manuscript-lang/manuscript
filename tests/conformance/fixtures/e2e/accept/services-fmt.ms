# conform: tags=faults,formatter,modules,optional,parser,stdlib-bytes,stdlib-collections,stdlib-string,stdlib-testing,strings,testing,tier-stdlib,try-result
# conform: phase=parse
# conform: origin=tests/e2e/testdata/accept/services.ms
import expect_equal from "@std/test.ms"
import BytesBuilder from "@std/bytes.ms"
import StringBuilder from "@std/string.ms"

test "builders":
    var bytes = BytesBuilder()
    bytes.append(65)
    bytes.append_bytes("B".to_bytes())

    let expected_text: Optional[String] = some("AB")
    try expect_equal(bytes.build().decode_utf8(), expected_text)

    var text = StringBuilder()
    text.append("hello")
    text.append(" world")
    try expect_equal(text.build(), "hello world")
