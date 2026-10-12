package project

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

// ResolveImport resolves a local import; standard imports belong to the checker.
func ResolveImport(project Project, importer, path string, overlay map[string]string) (string, error) {
	if strings.Contains(path, "\\") {
		return "", fmt.Errorf("import paths use / separators")
	}
	var target string
	if strings.HasPrefix(path, "./") || strings.HasPrefix(path, "../") {
		if filepath.Ext(path) != ".ms" {
			return "", fmt.Errorf("import path requires .ms extension")
		}
		target = filepath.Join(filepath.Dir(importer), path)
	} else if strings.HasPrefix(path, "@") {
		alias, remainder, _ := strings.Cut(path, "/")
		base := project.Aliases[alias]
		if base == "" {
			return "", fmt.Errorf("unknown import alias %s", alias)
		}
		info, err := os.Stat(base)
		if err != nil {
			return "", err
		}
		if info.IsDir() {
			if remainder == "" || filepath.Ext(remainder) != ".ms" {
				return "", fmt.Errorf("directory alias requires a .ms path")
			}
			target = filepath.Join(base, remainder)
		} else {
			if remainder != "" || filepath.Ext(base) != ".ms" {
				return "", fmt.Errorf("file alias does not accept a suffix")
			}
			target = base
		}
	} else {
		return "", fmt.Errorf("imports require a relative path or alias")
	}
	return SourcePath(project.Root, target, overlay)
}

// SourcePath canonicalizes a source path within root, which must be canonical.
// An overlay may supply a new file only beneath an existing, confined directory.
func SourcePath(root, path string, overlay map[string]string) (string, error) {
	if !filepath.IsAbs(path) {
		path = filepath.Join(root, path)
	}
	canonical, err := filepath.EvalSymlinks(path)
	if err != nil {
		if len(overlay) == 0 || !os.IsNotExist(err) {
			return "", err
		}
		// A dangling link is an existing entry, not a new editor file.
		if _, statErr := os.Lstat(path); statErr == nil || !os.IsNotExist(statErr) {
			return "", err
		}
		parent, parentErr := filepath.EvalSymlinks(filepath.Dir(path))
		if parentErr != nil {
			return "", parentErr
		}
		canonical = filepath.Join(parent, filepath.Base(path))
		_, writtenPath := overlay[filepath.Clean(path)]
		_, canonicalPath := overlay[canonical]
		if !writtenPath && !canonicalPath {
			return "", err
		}
	}
	rel, err := filepath.Rel(root, canonical)
	if err != nil || rel == ".." || strings.HasPrefix(rel, ".."+string(filepath.Separator)) {
		return "", fmt.Errorf("path escapes project root: %s", path)
	}
	return canonical, nil
}
