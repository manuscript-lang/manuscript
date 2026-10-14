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

// DiscoverModulesWithOverlay also includes new editor files that meet the same
// discovery rules. Overlay keys have already been confined and canonicalized.
func DiscoverModulesWithOverlay(p Project, includeSource bool, overlay map[string]string) ([]string, error) {
	files, err := DiscoverModules(p, includeSource)
	if err != nil {
		return nil, err
	}
	seen := make(map[string]bool, len(files))
	for _, file := range files {
		seen[file] = true
	}
	for file := range overlay {
		name := filepath.Base(file)
		if includeSource && filepath.Ext(name) == ".ms" && discoveredBelow(p.Source, file) || (name == "test.ms" || strings.HasSuffix(name, "_test.ms")) && discoveredBelow(p.Root, file) {
			seen[file] = true
		}
	}
	files = files[:0]
	for file := range seen {
		files = append(files, file)
	}
	sort.Strings(files)
	return files, nil
}

func discoveredBelow(root, file string) bool {
	rel, err := filepath.Rel(root, file)
	if err != nil || rel == ".." || strings.HasPrefix(rel, ".."+string(filepath.Separator)) || filepath.IsAbs(rel) {
		return false
	}
	for _, dir := range strings.Split(filepath.Dir(rel), string(filepath.Separator)) {
		if dir != "." && (strings.HasPrefix(dir, ".") || dir == "vendor" || dir == "node_modules") {
			return false
		}
	}
	return true
}
