package build

import (
	"fmt"
	"github.com/manuscript-lang/manuscript/pkg/compiler"
	"strings"
	"testing"
)

func TestNativeDefaultCallableBoundaries(t *testing.T) {
	const prefix = `import {base64_encode, base64_decode} from "@std/encoding.ms"
import {parse, CsvOptions} from "@std/csv.ms"
import {commands, Commands, CommandOutput, CommandError} from "@std/process.ms"
import {Bytes} from "@std/bytes.ms"
import Duration from "@std/time.ms"
fn forward[T](item: T) -> T: item
`
	for _, item := range []struct{ name, body, want string }{
		{"missing data", "base64_encode()", "missing argument data"},
		{"wrong bool", "base64_encode(Bytes([]), url_safe: none)", "expected Bool"},
		{"wrong options", "parse(\"a\", options: none)", "expected CsvOptions"},
		{"typed callable", "let f: fn(data: Bytes, url_safe: Bool) -> String = base64_encode\n    f(Bytes([]))", "missing argument url_safe"},
		{"mutable callable", "var f = base64_encode\n    f(Bytes([]))", "missing argument url_safe"},
		{"forwarded callable", "let f = forward(base64_encode)\n    f(Bytes([]))", "missing argument url_safe"},
		{"typed bound method", "let f: fn(program: String, arguments: List[String], input: Bytes, max_output_bytes: Optional[Int], timeout: Optional[Duration]) -> Result[CommandOutput, CommandError] = commands().run\n    f(program: \"\", arguments: [])", "missing argument input"},
	} {
		t.Run(item.name, func(t *testing.T) {
			r := compiler.CompileSource("boundary.ms", prefix+"fn check() -> Unit:\n    "+item.body+"\n", compiler.Options{AnalyzeOnly: true})
			if r.Success() || !strings.Contains(fmt.Sprint(r.Diagnostics), item.want) {
				t.Fatalf("want %s: %v", item.want, r.Diagnostics)
			}
		})
	}
}
