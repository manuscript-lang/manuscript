package msruntime

import (
	"errors"
	"io"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"unicode/utf8"
)

func init() {
	LibraryMethods = append(LibraryMethods, LibraryMethod{"FileSystem", "glob_entries", libraryResult("List[PathEntry]", "FileSystemError"), []LibraryParam{{"path", "String"}, {"options", "GlobOptions"}, {"exclude", "Optional[fn(entry:PathEntry)->Bool]"}}})
}
func (f *libraryFileSystem) globEntries(ctx *Execution, r string, a []Value) Value {
	root, ok := f.path(a[0].(string))
	fields := a[1].(Record).Fields
	patterns, excluded := libraryStringValues(fields["patterns"]), libraryStringValues(fields["exclude"])
	follow := fields["follow_links"].(bool)
	remaining, maxResults := nativeInteger(fields["max_entries"]), nativeInteger(fields["max_results"])
	if !ok || remaining < 0 || maxResults < 0 {
		return libraryError(r, "InvalidInput", "")
	}
	for _, pattern := range append(append([]string{}, patterns...), excluded...) {
		if !libraryValidGlob(filepath.ToSlash(pattern)) {
			return libraryError(r, "InvalidInput", "")
		}
	}
	exclusion := a[2].(Alternative)
	var callback Value
	if exclusion.Tag == "some" {
		callback = exclusion.Fields[0]
	}
	items := map[string]Value{}
	ancestors := map[string]bool{}
	var visit func(string) error
	visit = func(path string) error {
		CheckCancelled(ctx)
		if remaining == 0 {
			return errLibraryLimit
		}
		remaining--
		info, err := os.Lstat(path)
		if err != nil {
			return err
		}
		rel, err := filepath.Rel(root, path)
		if err != nil {
			return err
		}
		if !utf8.ValidString(rel) || !utf8.ValidString(info.Name()) {
			return errLibraryEncoding
		}
		value := Record{"@std/PathEntry", map[string]Value{"path": rel, "entry": Record{"@std/DirectoryEntry", map[string]Value{"name": info.Name(), "directory": info.IsDir(), "symlink": info.Mode()&os.ModeSymlink != 0}}}}
		candidate := filepath.ToSlash(rel)
		absolute := filepath.ToSlash(path)
		for _, pattern := range excluded {
			target := candidate
			if filepath.IsAbs(pattern) {
				target = absolute
			}
			if libraryGlobMatch(target, filepath.ToSlash(pattern)) {
				return nil
			}
		}
		if callback != nil && Invoke(ctx, callback, []Argument{{"entry", value}}).(bool) {
			return nil
		}
		for _, pattern := range patterns {
			target := candidate
			if filepath.IsAbs(pattern) {
				target = absolute
			}
			if libraryGlobMatch(target, filepath.ToSlash(pattern)) {
				if _, exists := items[rel]; !exists {
					if int64(len(items)) >= maxResults {
						return errLibraryLimit
					}
					items[rel] = value
				}
				break
			}
		}
		if info.Mode()&os.ModeSymlink != 0 && follow {
			info, err = os.Stat(path)
			if errors.Is(err, os.ErrNotExist) {
				return nil
			}
			if err != nil {
				return err
			}
		}
		if !info.IsDir() {
			return nil
		}
		canonical, err := filepath.EvalSymlinks(path)
		if err != nil {
			return err
		}
		if ancestors[canonical] {
			return nil
		}
		ancestors[canonical] = true
		defer delete(ancestors, canonical)
		directory, err := os.Open(path)
		if err != nil {
			return err
		}
		defer directory.Close()
		for {
			batch, err := directory.ReadDir(64)
			for _, entry := range batch {
				if err := visit(filepath.Join(path, entry.Name())); err != nil {
					return err
				}
			}
			if err == io.EOF {
				break
			}
			if err != nil {
				return err
			}
		}
		return nil
	}
	// Relative parent and absolute patterns can start outside cwd, as in Node.
	// The caller's filesystem capability already supplies that OS authority.
	roots := map[string]bool{root: true}
	for _, pattern := range patterns {
		pattern = filepath.FromSlash(pattern)
		base := root
		if filepath.IsAbs(pattern) {
			base = filepath.VolumeName(pattern) + string(os.PathSeparator)
			pattern = strings.TrimLeft(strings.TrimPrefix(pattern, filepath.VolumeName(pattern)), "/\\")
		}
		parts := strings.Split(pattern, string(os.PathSeparator))
		for _, part := range parts {
			if part == ".." {
				base = filepath.Dir(base)
			} else if part == "." || part == "" {
				continue
			} else if strings.ContainsAny(part, "*?[]{}()!") {
				break
			} else {
				base = filepath.Join(base, part)
			}
		}
		if info, err := os.Lstat(base); err == nil && info.IsDir() {
			roots[base] = true
		} else if base != root {
			roots[filepath.Dir(base)] = true
		}
	}
	starts := make([]string, 0, len(roots))
	for start := range roots {
		starts = append(starts, start)
	}
	sort.Slice(starts, func(i, j int) bool {
		if len(starts[i]) == len(starts[j]) {
			return starts[i] < starts[j]
		}
		return len(starts[i]) < len(starts[j])
	})
	var selected []string
	for _, start := range starts {
		covered := false
		for _, parent := range selected {
			rel, err := filepath.Rel(parent, start)
			if err == nil && (rel == "." || rel != ".." && !strings.HasPrefix(rel, ".."+string(os.PathSeparator))) {
				covered = true
				break
			}
		}
		if !covered {
			selected = append(selected, start)
		}
	}
	for _, start := range selected {
		if err := visit(start); err != nil {
			if errors.Is(err, os.ErrNotExist) {
				continue
			}
			if errors.Is(err, errLibraryEncoding) {
				return libraryError(r, "Unsupported", "")
			}
			return libraryCopyError(r, err)
		}
	}
	keys := make([]string, 0, len(items))
	for key := range items {
		keys = append(keys, key)
	}
	sort.Strings(keys)
	values := make([]Value, 0, len(keys))
	for _, key := range keys {
		values = append(values, items[key])
	}
	return libraryOK(r, libraryList("@std/PathEntry", values))
}
