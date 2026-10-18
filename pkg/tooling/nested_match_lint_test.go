package tooling

import (
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/compiler"
)

func TestNestedMatchLint(t *testing.T) {
	for _, tc := range []struct {
		name, source string
		want         int
	}{
		// manuscript:allow-nested-match tests the advisory on a nested statement and exact inner position
		{"statement", "fn use(value: Optional[Int]) Unit:\n    match value:\n        some(_):\n            match value:\n                some(_): unit\n                none: unit\n        none: unit\n", 1},
		// manuscript:allow-nested-match tests match expression values
		{"value", "fn use(value: Optional[Int]) Int:\n    return match value:\n        some(_):\n            match value:\n                some(n): n\n                none: 0\n        none: 0\n", 1},
		// manuscript:allow-nested-match inline callbacks remain structurally nested
		{"closure", "fn use(value: Optional[Int]) Int:\n    return match value:\n        some(_):\n            let callback = fn() Int:\n                return match value:\n                    some(n): n\n                    none: 0\n            callback()\n        none: 0\n", 1},
		// manuscript:allow-nested-match default expressions must share structural traversal
		{"default", "fn use(value: Optional[Int]) Int:\n    return match value:\n        some(_):\n            let callback = fn(n: Int = match value:\n                some(x): x\n                none: 0\n            ) Int:\n                return n\n            callback()\n        none: 0\n", 1},
		// manuscript:allow-nested-match the scrutinee can itself contain a match
		{"scrutinee", "fn use(value: Optional[Int]) Int:\n    return match (\n        match value:\n            some(x): some(x)\n            none: some(0)\n    ):\n        some(x): x\n        none: 0\n", 1},
		// manuscript:allow-nested-match each inner level must warn once
		{"three levels", "fn use(value: Optional[Int]) Int:\n    return match value:\n        some(_):\n            match value:\n                some(_):\n                    match value:\n                        some(n): n\n                        none: 0\n                none: 0\n        none: 0\n", 2},
		{"flat early exit", "fn use(value: Optional[Int]) Int:\n    let present = match value:\n        some(n): n\n        none: return 0\n    return match value:\n        some(n): present + n\n        none: 0\n", 0},
		{"helper", "fn inner(value: Optional[Int]) Int:\n    return match value:\n        some(n): n\n        none: 0\nfn use(value: Optional[Int]) Int:\n    return match value:\n        some(_): inner(value)\n        none: 0\n", 0},
		{"text", "fn use() String: \"match nested match\"\n", 0},
	} {
		for _, newline := range []string{"\n", "\r\n"} {
			t.Run(tc.name+newline, func(t *testing.T) {
				source := strings.ReplaceAll(tc.source, "\n", newline)
				checked := compiler.CompileSource("nested.ms", source, compiler.Options{AnalyzeOnly: true})
				if !checked.Success() {
					t.Fatal(checked.Diagnostics)
				}
				var offsets []int
				for _, finding := range LintProgram(checked.Program) {
					if finding.Code != "MSL107" {
						continue
					}
					if finding.Position.File != "nested.ms" || !strings.HasPrefix(source[finding.Position.Offset:], "match") || !strings.Contains(finding.Message, "helper") {
						t.Fatalf("wrong nested-match finding: %+v", finding)
					}
					offsets = append(offsets, finding.Position.Offset)
				}
				if len(offsets) != tc.want {
					t.Fatalf("got %v, want %d advisories", offsets, tc.want)
				}
				if tc.want == 1 && offsets[0] != strings.LastIndex(source, "match") {
					t.Fatalf("warning did not locate inner match: %v", offsets)
				}
			})
		}
	}
}
