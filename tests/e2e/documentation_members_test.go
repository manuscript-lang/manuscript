package e2e_test

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/checker"
)

func TestCLIMemberDocumentation(t *testing.T) {
	file := filepath.Join(t.TempDir(), "members.ms")
	source := `# A described record.
export type Data:
    # Count in items.
    count: Int = 0

export type Outcome:
    # Work completed.
    case Ready(value: Int)

export interface Readable:
    # Reads the count.
    fn read() -> Int

impl Readable for Data:
    # Returns the stored count.
    fn read() -> Int:
        return self.count
`
	if err := os.WriteFile(file, []byte(source), 0600); err != nil {
		t.Fatal(err)
	}
	output, err := commandOutput(t, cliBinary, "doc", file)
	if err != nil {
		t.Fatalf("doc: %v\n%s", err, output)
	}
	for _, phrase := range []string{"### Data.count", "Count in items.", "### Outcome.Ready", "Work completed.", "### Readable.read", "Reads the count.", "### Data.Readable.read", "Returns the stored count."} {
		if !strings.Contains(string(output), phrase) {
			t.Fatalf("missing %q: %s", phrase, output)
		}
	}
	output, err = commandOutput(t, cliBinary, "doc", file, "--json")
	if err != nil {
		t.Fatalf("doc --json: %v\n%s", err, output)
	}
	var decoded struct {
		Format  int
		Modules []checker.APIModule
	}
	if err := json.Unmarshal(output, &decoded); err != nil {
		t.Fatal(err)
	}
	if decoded.Format != 1 || len(decoded.Modules) != 1 {
		t.Fatal(string(output))
	}
	found := false
	for _, d := range decoded.Modules[0].Declarations {
		if d.Name != "Data" {
			continue
		}
		if len(d.Fields) != 1 || d.Fields[0] != "count: Int" {
			t.Fatal("legacy fields changed", d)
		}
		for _, member := range d.Members {
			if member.Name == "count" && member.Doc == "Count in items." {
				found = true
			}
		}
	}
	if !found {
		t.Fatal("structured member description missing", string(output))
	}
	output, err = commandOutput(t, cliBinary, "doc", "--stdlib")
	if err != nil || !strings.Contains(string(output), "### Bytes.values") || !strings.Contains(string(output), "### String.slice") {
		t.Fatalf("native/intrinsic descriptions missing: %v", err)
	}
}
