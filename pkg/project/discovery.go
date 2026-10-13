package project

import (
	"os"
	"path/filepath"
	"sort"
	"strings"
)

// DiscoverModules finds project test.ms and *_test.ms files. With includeSource,
// it also finds every .ms file below the configured source directory. Discovery
// skips hidden and dependency directories and does not follow directory symlinks;
// explicitly loaded entries and imports still use ordinary path resolution.
// Traversal errors are returned so callers cannot report a partial scan as success.
func DiscoverModules(p Project, includeSource bool) ([]string, error) {
	files := map[string]bool{}
	walk := func(root string, all bool) error {
		return filepath.WalkDir(root, func(path string, entry os.DirEntry, err error) error {
			if err != nil {
				return err
			}
			name := entry.Name()
			if entry.IsDir() {
				if path != root && (strings.HasPrefix(name, ".") || name == "vendor" || name == "node_modules") {
					return filepath.SkipDir
				}
				return nil
			}
			if all && filepath.Ext(name) == ".ms" || name == "test.ms" || strings.HasSuffix(name, "_test.ms") {
				files[path] = true
			}
			return nil
		})
	}
	if includeSource {
		if err := walk(p.Source, true); err != nil {
			return nil, err
		}
	}
	if err := walk(p.Root, false); err != nil {
		return nil, err
	}
	result := make([]string, 0, len(files))
	for file := range files {
		result = append(result, file)
	}
	sort.Strings(result)
	return result, nil
}
