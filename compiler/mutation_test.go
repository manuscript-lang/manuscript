package compiler_test

import (
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/compiler"
)

func TestMutationRejections(t *testing.T) {
	declarations := `import List from "@std/collections.ms"
import stdout from "@std/io.ms"
import File from "@std/io.ms"
import Synchronized from "@std/sync.ms"
import SynchronizedGuard from "@std/sync.ms"
interface Read:
    fn get() -> Int
type Val:
    val: Int
impl Read for Val:
    fn get() -> Int:
        return self.val
`
	for _, test := range []struct{ name, source, message string }{
		{"field type", "fn f(value: Val) -> Unit:\n    value.val = true\n", "expected Int"},
		{"missing field", "fn f(value: Val) -> Unit:\n    value.missing = 1\n", "unknown or ambiguous member"},
		{"type field assignment", "fn f() -> Unit:\n    Val.val = 1\n", "assignment requires a record field"},
		{"method assignment", "fn f(value: Val) -> Unit:\n    value.get = 1\n", "assignment requires a record field"},
		{"local binding remains fixed", "fn f() -> Unit:\n    let value = Val(val: 0)\n    value = Val(val: 1)\n", "cannot assign immutable binding"},
		{"parameter binding remains fixed", "fn f(value: Val) -> Unit:\n    value = Val(val: 1)\n", "cannot assign immutable binding"},
		{"resource clone", "fn f() -> Unit:\n    stdout().clone()\n", "unknown or ambiguous member clone"},
		{"file clone", "fn f(file: File) -> Unit:\n    file.clone()\n", "unknown or ambiguous member clone"},
		{"socket clone", "import Connection from \"@std/net.ms\"\nfn f(socket: Connection) -> Unit:\n    socket.clone()\n", "unknown or ambiguous member clone"},
		{"lock clone", "fn f(lock: Synchronized[Int]) -> Unit:\n    lock.clone()\n", "unknown or ambiguous member clone"},
		{"guard clone", "fn f(guard: SynchronizedGuard[Int]) -> Unit:\n    guard.clone()\n", "unknown or ambiguous member clone"},
		{"service fields opaque", "fn f(lock: Synchronized[Int]) -> Unit:\n    lock.value = 1\n", "assignment requires a record field"},
	} {
		t.Run(test.name, func(t *testing.T) {
			result := compiler.CompileSource("rejected.ms", declarations+test.source, compiler.Options{})
			if result.Success() {
				t.Fatal("accepted invalid mutation or clone")
			}
			found := false
			for _, issue := range result.Diagnostics {
				found = found || strings.Contains(issue.Message, test.message)
			}
			if !found {
				t.Fatal(result.Diagnostics)
			}
		})
	}
}
