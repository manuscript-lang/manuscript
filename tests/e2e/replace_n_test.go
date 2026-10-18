package e2e_test

import (
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/compiler"
)

func TestReplaceNRequiresFiniteCountAndPreservesCallableShape(t *testing.T) {
	for _, statement := range []string{
		`"a".replace_n("a", "b")`,
		`"a".replace_n("a", "b", none)`,
		`"a".replace_n("a", "b", some(1))`,
		`"a".replace_n("a", "b", 1.5)`,
		`"a".replace_n(old: "a", new: "b", max_bytes: 1)`,
		`let replace: fn(old: String, new: String) String = "a".replace_n`,
		`let replace = "a".replace_n
    replace("a", "b")`,
	} {
		checked := compiler.CompileSource("replace-count.ms", "fn use() Unit:\n    "+statement+"\n", compiler.Options{AnalyzeOnly: true})
		if checked.Success() {
			t.Fatalf("accepted missing/optional count or changed callable: %s", statement)
		}
	}
}

func TestReplaceNRetainsNegativeFaultsAndFrames(t *testing.T) {
	source := `test "legacy negative":
    "a".replace("a", "b", -1)
test "required negative":
    "a".replace_n("a", "b", -1)
test "bound negative":
    let replace = "a".replace_n
    replace("a", "b", -1)
test "empty negative":
    "".replace_n("", "b", -1)
test "continues":
    let _unchanged = "a".replace_n("a", "b", 0)
`
	data, err := execute(t, compiler.CompileSource("replace-n-faults.ms", source, compiler.Options{Tests: true}))
	if err == nil {
		t.Fatal("missing negative faults", string(data))
	}
	output := string(data)
	var message string
	for _, name := range []string{"legacy negative", "required negative", "bound negative", "empty negative"} {
		_, tail, found := strings.Cut(output, "FAIL replace-n-faults.ms::"+name+": ")
		if !found {
			t.Fatal(output)
		}
		current, _, _ := strings.Cut(tail, "\n")
		if message != "" && current != message {
			t.Fatalf("changed legacy fault: %q != %q", message, current)
		}
		message = current
	}
	for _, frame := range []string{"replace-n-faults.ms:4", "replace-n-faults.ms:7", "replace-n-faults.ms:9", "5 tests, 4 failed"} {
		if !strings.Contains(output, frame) {
			t.Errorf("missing %s: %s", frame, output)
		}
	}
}
