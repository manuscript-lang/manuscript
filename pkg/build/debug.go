package build

import (
	"github.com/manuscript-lang/manuscript/pkg/compiler"
	"path/filepath"
	"strings"
)

// debugSource binds generated line directives to the actual source tree. Native
// release builds retain portable logical paths; builds with debugging information include this root.
func debugSource(result compiler.Result) string {
	if result.SourceRoot == "" {
		return result.Source
	}
	paths := map[string]string{}
	for _, m := range result.Program.Modules {
		paths[m.File] = filepath.Join(result.SourceRoot, filepath.FromSlash(m.File))
	}
	lines := strings.Split(result.Source, "\n")
	for index, line := range lines {
		if !strings.HasPrefix(line, "//line ") {
			continue
		}
		directive := strings.TrimPrefix(line, "//line ")
		colon := strings.LastIndexByte(directive, ':')
		if colon < 0 {
			continue
		}
		if absolute, ok := paths[directive[:colon]]; ok {
			absolute = strings.NewReplacer("\n", "_", "\r", "_").Replace(absolute)
			lines[index] = "//line " + absolute + directive[colon:]
		}
	}
	return strings.Join(lines, "\n")
}
