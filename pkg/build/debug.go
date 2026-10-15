package build

import (
	"github.com/manuscript-lang/manuscript/pkg/compiler"
	"path/filepath"
	"regexp"
	"strings"
)

// directivePattern matches both the line form (//line file:N) at the start of a
// line and the inline form (/*line file:N*/) that lowering repeats before calls.
var directivePattern = regexp.MustCompile(`(^//line |/\*line )([^\n]*?)(:\d+)`)

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
		lines[index] = directivePattern.ReplaceAllStringFunc(line, func(match string) string {
			parts := directivePattern.FindStringSubmatch(match)
			absolute, ok := paths[parts[2]]
			if !ok {
				return match
			}
			absolute = strings.NewReplacer("\n", "_", "\r", "_").Replace(absolute)
			return parts[1] + absolute + parts[3]
		})
	}
	return strings.Join(lines, "\n")
}
