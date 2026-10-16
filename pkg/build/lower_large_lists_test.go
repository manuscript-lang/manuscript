package build

import (
	"fmt"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/compiler"
)

func listOf(items []string) string { return "[" + strings.Join(items, ", ") + "]" }

func repeated(n int, item func(int) string) []string {
	items := make([]string, n)
	for i := range items {
		items[i] = item(i)
	}
	return items
}

// A fault raised by an item past the first chunk reports the same source
// frames as the single-expression lowering Debug builds keep.
func TestLargeListLiteralFaultFrames(t *testing.T) {
	items := repeated(300, func(i int) string { return fmt.Sprintf("value(%d)", i) })
	items[200] = "fail()"
	source := "fn value(i: Int) -> Int: i\nfn fail() -> Int:\n    return 1 / 0\nexport fn main() -> Int:\n    let data = " + listOf(items) + "\n    return data.length\n"
	var transcripts []string
	for _, kind := range []compiler.BuildType{compiler.Release, compiler.Debug} {
		r := compiler.CompileSourceForBuild("fault.ms", source, compiler.Options{Entry: true}, kind)
		if !r.Success() {
			t.Fatal(r.Diagnostics)
		}
		binary := filepath.Join(t.TempDir(), "program")
		if _, err := BuildCheckedWithType(r, binary, kind); err != nil {
			t.Fatal(err)
		}
		data, err := exec.Command(binary).CombinedOutput()
		if err == nil {
			t.Fatal("expected fault")
		}
		transcripts = append(transcripts, string(data))
	}
	if transcripts[0] != transcripts[1] || !strings.Contains(transcripts[0], "fault.ms:3 in fail") || !strings.Contains(transcripts[0], "fault.ms:5 in main") {
		t.Fatalf("fault frames changed: %q", transcripts)
	}
}
