package e2e_test

import (
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/compiler"
)

func TestLocalClosureFaultNamesTheLambda(t *testing.T) {
	result := compiler.CompileSource("closure-fault.ms", `import panic from "@std/faults.ms"

fn run() Int:
    let boom = fn(value: Int) Int: panic(message: "closure failed")
    return boom(value: 1)

test "fault":
    run()
`, compiler.Options{Tests: true})
	output, _ := execute(t, result)
	if !strings.Contains(string(output), "closure failed") || !strings.Contains(string(output), "in <anonymous>") || !strings.Contains(string(output), "in run") {
		t.Fatalf("fault frames lost the lambda\n%s", output)
	}
}
