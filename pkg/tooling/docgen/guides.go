package docgen

import (
	"fmt"
	"io/fs"
	"path"
	"strings"

	"github.com/manuscript-lang/manuscript/pkg/stdlib"
)

// GuideFiles renders documentation blocks in the pinned Manuscript sources.
// Blocks are ordinary comments, separated from declaration hover comments:
// # documentation documentation/standard-library/example.md
// # +++
// # title = "Example"
// # +++
// # end-documentation
func GuideFiles() (map[string][]byte, error) { return guideFiles(stdlib.Sources) }

func guideFiles(sources fs.FS) (map[string][]byte, error) {
	files := map[string][]byte{}
	names, err := fs.Glob(sources, "*.ms")
	if err != nil {
		return nil, err
	}
	for _, name := range names {
		data, err := fs.ReadFile(sources, name)
		if err != nil {
			return nil, err
		}
		var target string
		var body strings.Builder
		for index, line := range strings.Split(strings.TrimSuffix(string(data), "\n"), "\n") {
			fail := func(message string) (map[string][]byte, error) {
				return nil, fmt.Errorf("%s:%d: %s", name, index+1, message)
			}
			if strings.HasPrefix(line, "# documentation ") {
				if target != "" {
					return fail("nested documentation block")
				}
				target = strings.TrimPrefix(line, "# documentation ")
				if path.Clean(target) != target || path.Ext(target) != ".md" || !(strings.HasPrefix(target, "documentation/standard-library/") || strings.HasPrefix(target, "documentation/concurrency/")) {
					return fail("invalid documentation path")
				}
				if _, exists := files[target]; exists {
					return fail("duplicate documentation path")
				}
				body.Reset()
			} else if line == "# end-documentation" {
				if target == "" {
					return fail("unexpected documentation terminator")
				}
				files[target] = []byte(body.String())
				target = ""
			} else if target != "" {
				if line == "#" {
					body.WriteByte('\n')
				} else if strings.HasPrefix(line, "# ") {
					body.WriteString(strings.TrimPrefix(line, "# "))
					body.WriteByte('\n')
				} else {
					return fail("documentation must use top-level comments")
				}
			}
		}
		if target != "" {
			return nil, fmt.Errorf("%s: unterminated documentation block", name)
		}
	}
	return files, nil
}

func specialCallRules() string {
	files, err := GuideFiles()
	if err != nil {
		panic(err)
	}
	rules, exists := files["documentation/standard-library/call-rules.md"]
	if !exists {
		panic("standard sources omit special call rules")
	}
	return string(rules)
}
