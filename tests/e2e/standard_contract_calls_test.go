package e2e_test

import (
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/compiler"
)

func TestStandardContractCallsReuseOperationsPerSite(t *testing.T) {
	result := compiler.CompileSource("contract-calls.ms", `import panic from "@std/faults.ms"
import {stdout} from "@std/io.ms"
import {clock} from "@std/time.ms"

fn check(ok: Bool, name: String) -> Unit:
    if not ok:
        return panic(message: name)

type Boom:
    code: Int

impl Error for Boom:
    fn message() -> String: "boom {self.code}"

fn describe(e: Error) -> String: e.message()

test "repeated calls through one site":
    let c = clock()
    var i = 0
    while i < 3:
        let a = c.now()
        let b = c.now()
        check(ok: b.difference(other: a).to_milliseconds() >= 0, name: "monotonic")
        i = i + 1
    let out = stdout()
    var n = 0
    while n < 2:
        check(ok: out.write(data: "x".to_bytes()).is_ok(), name: "write")
        n = n + 1
    check(ok: describe(e: Error(value: Boom(code: 1))) == "boom 1", name: "user error")
    check(ok: describe(e: Error(value: Boom(code: 2))) == "boom 2", name: "user error again")
`, compiler.Options{Tests: true})
	output, err := execute(t, result)
	if err != nil || !strings.Contains(string(output), "PASS") {
		t.Fatalf("contract calls changed: %v\n%s", err, output)
	}
}
