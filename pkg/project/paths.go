package project

import (
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
)

// ResolveImport resolves a local import; standard imports belong to the checker.
func ResolveImport(project Project, importer, path string, overlay map[string]string) (string, error) {
	if strings.Contains(path, "\\") {
		return "", fmt.Errorf("import paths use / separators; write \"./dir/file.ms\" instead of backslashes")
	}
	var target string
	if strings.HasPrefix(path, "./") || strings.HasPrefix(path, "../") {
		if filepath.Ext(path) != ".ms" {
			return "", fmt.Errorf("import path requires .ms extension; write \"%s.ms\"", strings.TrimSuffix(path, filepath.Ext(path)))
		}
		target = filepath.Join(filepath.Dir(importer), path)
	} else if strings.HasPrefix(path, "@") {
		alias, remainder, _ := strings.Cut(path, "/")
		base := project.Aliases[alias]
		if base == "" {
			return "", fmt.Errorf("unknown import alias %s%s", alias, aliasHint(project.Aliases))
		}
		info, err := os.Stat(base)
		if err != nil {
			return "", err
		}
		if info.IsDir() {
			if remainder == "" || filepath.Ext(remainder) != ".ms" {
				return "", fmt.Errorf("directory alias requires a .ms path; write \"%s/<file>.ms\"", alias)
			}
			target = filepath.Join(base, remainder)
		} else {
			if remainder != "" || filepath.Ext(base) != ".ms" {
				return "", fmt.Errorf("file alias does not accept a suffix; alias %s names one file, so import it as \"%s\" alone", alias, alias)
			}
			target = base
		}
	} else if strings.HasPrefix(path, "/") {
		return "", fmt.Errorf("absolute import paths are not supported; write a relative path such as \"../name.ms\" from this file, or declare an alias under [aliases] in ms.toml")
	} else {
		return "", fmt.Errorf("imports require a relative path or alias; write \"./%s\" for a file next to this one, \"@std/name.ms\" for the standard library, or declare an alias under [aliases] in ms.toml", path)
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
		return "", fmt.Errorf("path escapes project root: %s; keep imported files inside the directory containing ms.toml (or the entry file's directory)", path)
	}
	return canonical, nil
}

func aliasHint(aliases map[string]string) string {
	if len(aliases) == 0 {
		return "; this project declares none, so add one under [aliases] in ms.toml, e.g. @lib = \"src/lib\" (use @std/... for the standard library)"
	}
	names := make([]string, 0, len(aliases))
	for name := range aliases {
		names = append(names, name)
	}
	sort.Strings(names)
	return "; declared aliases: " + strings.Join(names, ", ")
}
