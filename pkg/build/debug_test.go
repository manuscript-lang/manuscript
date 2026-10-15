package build

import (
	"path/filepath"
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/compiler"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

func TestDebugSourceRewritesLineAndInlineDirectives(t *testing.T) {
	root := t.TempDir()
	result := compiler.Result{
		SourceRoot: root,
		Program:    &checker.Program{Modules: []*syntax.Module{{File: "main.ms"}}},
		Source:     "//line main.ms:3\nx := 1\n\tf(/*line main.ms:7*/g())\n//line other.ms:2\n",
	}
	got := debugSource(result)
	absolute := filepath.Join(root, "main.ms")
	for _, want := range []string{"//line " + absolute + ":3", "/*line " + absolute + ":7*/g()", "//line other.ms:2"} {
		if !strings.Contains(got, want) {
			t.Errorf("missing %q in\n%s", want, got)
		}
	}
}
