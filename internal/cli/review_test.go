package cli

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

const reviewHead = "fn add(a: Int, b: Int) Int:\n    let total = a + b\n    return total\n\nexport fn main() Int:\n    return add(1, 2)\n"

const reviewPatch = `--- a/main.ms
+++ b/main.ms
@@ -1,3 +1,4 @@
 fn add(a: Int, b: Int) Int:
-    return a + b
+    let total = a + b
+    return total
 
`

func TestReviewProjectAndDiff(t *testing.T) {
	file := sourceFile(t, reviewHead)
	status, output, errors := invoke(t, "review", file)
	if status != 0 || errors != "" || !strings.Contains(output, "PUBLIC SURFACE") || !strings.Contains(output, "digest sha256:") {
		t.Fatalf("project: %d, %q, %q", status, output, errors)
	}
	patch := filepath.Join(filepath.Dir(file), "change.patch")
	if err := os.WriteFile(patch, []byte(reviewPatch), 0600); err != nil {
		t.Fatal(err)
	}
	status, output, errors = invoke(t, "review", file, "--diff", patch)
	if status != 0 || errors != "" || !strings.Contains(output, "0 need attention, 1 internal") || !strings.Contains(output, "add (body changed)") {
		t.Fatalf("diff: %d, %q, %q", status, output, errors)
	}
	_, again, _ := invoke(t, "review", file, "--diff", patch)
	if again != output {
		t.Fatal("review output differs between runs")
	}
}

func TestReviewRejectsADiffThatDoesNotMatchTheTree(t *testing.T) {
	file := sourceFile(t, strings.ReplaceAll(reviewHead, "total", "sum"))
	patch := filepath.Join(filepath.Dir(file), "change.patch")
	if err := os.WriteFile(patch, []byte(reviewPatch), 0600); err != nil {
		t.Fatal(err)
	}
	status, output, errors := invoke(t, "review", file, "--diff", patch)
	if status != 2 || output != "" || !strings.Contains(errors, "diff does not match the tree") {
		t.Fatalf("%d, %q, %q", status, output, errors)
	}
}

func TestReviewAndDiagramFormats(t *testing.T) {
	file := sourceFile(t, reviewHead)
	status, output, _ := invoke(t, "review", file, "--json")
	if status != 0 || !strings.Contains(output, `"mode": "project"`) {
		t.Fatalf("json: %d %q", status, output)
	}
	if status, _, errors := invoke(t, "review", file, "--format", "xml"); status != 2 || !strings.Contains(errors, "use ascii or markdown") {
		t.Fatalf("format: %d %q", status, errors)
	}
	if status, _, errors := invoke(t, "review", file, "--json", "--format", "markdown"); status != 2 || !strings.Contains(errors, "cannot be combined") {
		t.Fatalf("json with format: %d %q", status, errors)
	}
	_, ascii, _ := invoke(t, "diagram", file)
	_, mermaid, _ := invoke(t, "diagram", file, "--format", "mermaid")
	if !strings.HasPrefix(ascii, "CALL GRAPH\n") || !strings.HasPrefix(mermaid, "flowchart TD") {
		t.Fatalf("ascii=%q mermaid=%q", ascii, mermaid)
	}
	if status, _, errors := invoke(t, "diagram", file, "--format", "dot"); status != 2 || !strings.Contains(errors, "use ascii or mermaid") {
		t.Fatalf("diagram format: %d %q", status, errors)
	}
	if status, _, errors := invoke(t, "inspect", file, "--format", "ascii"); status != 2 || !strings.Contains(errors, "--format is valid only") {
		t.Fatalf("inspect format: %d %q", status, errors)
	}
}

func TestDiagramViews(t *testing.T) {
	file := sourceFile(t, reviewHead)
	status, output, errors := invoke(t, "diagram", file, "--view", "calls", "--entity", "main")
	if status != 0 || errors != "" || !strings.Contains(output, "main  [fn]") || !strings.Contains(output, "add  [fn]") {
		t.Fatalf("calls: %d %q %q", status, output, errors)
	}
	if status, _, errors := invoke(t, "diagram", file, "--view", "sankey"); status != 2 || !strings.Contains(errors, "unknown --view") {
		t.Fatalf("view: %d %q", status, errors)
	}
	if status, _, errors := invoke(t, "diagram", file, "--entity", "nope"); status != 2 || !strings.Contains(errors, "no entity named nope") {
		t.Fatalf("entity: %d %q", status, errors)
	}
	if status, _, errors := invoke(t, "diagram", file, "--depth", "2"); status != 2 || !strings.Contains(errors, "--depth needs") {
		t.Fatalf("depth: %d %q", status, errors)
	}
	if status, _, errors := invoke(t, "inspect", file, "--view", "calls"); status != 2 || !strings.Contains(errors, "valid only for ms diagram") {
		t.Fatalf("inspect view: %d %q", status, errors)
	}
}

func TestDiagramFlowAndScopeNeedAnEntity(t *testing.T) {
	file := sourceFile(t, reviewHead)
	status, output, errors := invoke(t, "diagram", file, "--view", "flow", "--entity", "main")
	if status != 0 || errors != "" || !strings.Contains(output, "call add") || !strings.Contains(output, "return add(1, 2)") {
		t.Fatalf("flow: %d %q %q", status, output, errors)
	}
	if status, _, errors := invoke(t, "diagram", file, "--view", "scope"); status != 2 || !strings.Contains(errors, "scope needs --entity") {
		t.Fatalf("scope: %d %q", status, errors)
	}
}

func TestReviewExplainAndDiagramDiff(t *testing.T) {
	file := sourceFile(t, reviewHead)
	patch := filepath.Join(filepath.Dir(file), "change.patch")
	if err := os.WriteFile(patch, []byte(reviewPatch), 0600); err != nil {
		t.Fatal(err)
	}
	status, output, errors := invoke(t, "review", file, "--diff", patch, "--explain", "add")
	if status != 0 || errors != "" || !strings.Contains(output, "EXPLAIN add") || !strings.Contains(output, "CALLERS") || !strings.Contains(output, "body changed") {
		t.Fatalf("explain: %d %q %q", status, output, errors)
	}
	_, again, _ := invoke(t, "review", file, "--diff", patch, "--explain", "add")
	if again != output {
		t.Fatal("explain differs between runs")
	}
	if status, _, errors := invoke(t, "review", file, "--diff", patch, "--explain", "9"); status != 2 || !strings.Contains(errors, "no finding 9") {
		t.Fatalf("missing: %d %q", status, errors)
	}
	if status, _, errors := invoke(t, "review", file, "--explain", "1"); status != 2 || !strings.Contains(errors, "--explain needs --diff") {
		t.Fatalf("no diff: %d %q", status, errors)
	}
	status, output, errors = invoke(t, "diagram", file, "--view", "calls", "--entity", "main", "--diff", patch)
	if status != 0 || errors != "" || !strings.Contains(output, "add  [fn]") || !strings.Contains(output, "<- INTERNAL") {
		t.Fatalf("diagram diff: %d %q %q", status, output, errors)
	}
	if status, _, errors := invoke(t, "diagram", file, "--diff", patch); status != 2 || !strings.Contains(errors, "--diff marks a scoped view") {
		t.Fatalf("scope: %d %q", status, errors)
	}
}
