package docgen

import (
	"embed"
	"fmt"
	"io/fs"
	"path"
	"strings"
)

//go:embed guides/documentation
var guideSources embed.FS

// GuideFiles returns the authored standard-library and concurrency guides.
func GuideFiles() (map[string][]byte, error) { return guideFiles(guideSources) }

func guideFiles(sources fs.FS) (map[string][]byte, error) {
	files := map[string][]byte{}
	err := fs.WalkDir(sources, "guides/documentation", func(name string, entry fs.DirEntry, walkErr error) error {
		if walkErr != nil { return walkErr }
		if entry.IsDir() {
			return nil
		}
		target := strings.TrimPrefix(name, "guides/")
		if path.Clean(target) != target || path.Ext(target) != ".md" || !(strings.HasPrefix(target, "documentation/standard-library/") || strings.HasPrefix(target, "documentation/concurrency/")) {
			return fmt.Errorf("invalid documentation path: %s", target)
		}
		data, err := fs.ReadFile(sources, name)
		if err != nil {
			return err
		}
		files[target] = data
		return nil
	})
	if err != nil {
		return nil, err
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
