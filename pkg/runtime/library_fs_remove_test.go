package msruntime

import (
	"fmt"
	"os"
	"path/filepath"
	"testing"
)

func TestFileSystemRemoveProtectedPaths(t *testing.T) {
	// Every operation target is inside this disposable tree. Root paths are
	// checked by the validation helper alone, never passed to removal.
	parent := t.TempDir()
	base := filepath.Join(parent, "base")
	if err := os.MkdirAll(filepath.Join(base, "child"), 0700); err != nil {
		t.Fatal(err)
	}
	sentinel := filepath.Join(base, "child", "keep")
	if err := os.WriteFile(sentinel, []byte("untouched"), 0600); err != nil {
		t.Fatal(err)
	}
	fs := &libraryFileSystem{base}
	paths := []string{"", ".", "./", "..", "../", "child/..", "child/../.", "child/.", base, base + string(os.PathSeparator), filepath.Join(parent, "base") + "/child/..", parent}
	if err := os.Symlink(parent, filepath.Join(base, "alias")); err == nil {
		paths = append(paths, "alias/base", "alias/base/", "alias/base/child/..")
	}
	for _, recursive := range []bool{false, true} {
		for _, path := range paths {
			t.Run(fmt.Sprintf("%s/recursive=%t", path, recursive), func(t *testing.T) {
				libraryFailure(t, fs.Operation("remove").Body(RootExecution(), []Value{path, recursive}), "InvalidInput")
				if data, err := os.ReadFile(sentinel); err != nil || string(data) != "untouched" {
					t.Fatalf("sentinel changed: %q, %v", data, err)
				}
			})
		}
	}
	root := filepath.VolumeName(base) + string(os.PathSeparator)
	for _, path := range []string{root, root + ".", root + ".."} {
		if _, err := fs.removalPath(path); err != errLibraryInput {
			t.Fatalf("root %q: %v", path, err)
		}
	}
}

func TestFileSystemRemoveDescendantsAndLinks(t *testing.T) {
	base := t.TempDir()
	fs := &libraryFileSystem{base}
	for _, path := range []string{"tree/child", " space "} {
		if err := os.MkdirAll(filepath.Join(base, path), 0700); err != nil {
			t.Fatal(err)
		}
	}
	sentinel := filepath.Join(base, "keep")
	if err := os.WriteFile(sentinel, []byte("keep"), 0600); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(base, filepath.Join(base, "link")); err == nil {
		librarySuccess(t, fs.Operation("remove").Body(RootExecution(), []Value{"link/", true}))
		if _, err := os.Lstat(filepath.Join(base, "link")); !os.IsNotExist(err) {
			t.Fatal("link remains", err)
		}
	}
	for _, path := range []string{"tree/", " space ", "missing"} {
		librarySuccess(t, fs.Operation("remove").Body(RootExecution(), []Value{path, true}))
		if _, err := os.Stat(filepath.Join(base, path)); !os.IsNotExist(err) {
			t.Fatal("target remains", path, err)
		}
	}
	if data, err := os.ReadFile(sentinel); err != nil || string(data) != "keep" {
		t.Fatal("followed link", err)
	}
	librarySuccess(t, fs.Operation("remove").Body(RootExecution(), []Value{"keep", false}))
	libraryFailure(t, fs.Operation("remove").Body(RootExecution(), []Value{"missing", false}), "NotFound")
}

func TestFileSystemEmptyPaths(t *testing.T) {
	base := t.TempDir()
	fs := &libraryFileSystem{base}
	sentinel := filepath.Join(base, "keep")
	if err := os.WriteFile(sentinel, []byte("keep"), 0600); err != nil {
		t.Fatal(err)
	}
	// Early validation runs before interpreting the remaining operation arguments.
	for _, name := range []string{"read_file", "write_file", "stat", "list", "create_directory", "remove", "rename", "copy_file", "canonicalize", "read_link", "create_link", "access", "append_file", "chmod", "chown", "truncate", "set_times", "hard_link", "open", "open_flags", "open_directory", "copy_tree", "glob", "watch", "watch_native", "stat_filesystem", "chmod_link"} {
		t.Run(name, func(t *testing.T) {
			libraryFailure(t, fs.Operation(name).Body(RootExecution(), []Value{""}), "InvalidInput")
		})
	}
	for _, name := range []string{"rename", "hard_link", "create_link"} {
		libraryFailure(t, fs.Operation(name).Body(RootExecution(), []Value{"keep", ""}), "InvalidInput")
	}
	libraryFailure(t, fs.Operation("copy_file").Body(RootExecution(), []Value{"keep", "", true, int64(10)}), "InvalidInput")
	libraryFailure(t, fs.Operation("copy_tree").Body(RootExecution(), []Value{"keep", "", true, int64(10), int64(10)}), "InvalidInput")
	copyOptions := Record{"@std/CopyOptions", map[string]Value{"recursive": true, "replace": true, "error_on_exists": false, "dereference": false, "preserve_timestamps": false, "verbatim_symlinks": false, "clone": "none", "max_entries": int64(10), "max_bytes": int64(10)}}
	noFilter := optional("fn(source:String;destination:String)->Bool", nil, false)
	for _, paths := range [][2]string{{"", "destination"}, {"keep", ""}} {
		libraryFailure(t, fs.Operation("copy").Body(RootExecution(), []Value{paths[0], paths[1], copyOptions, noFilter}), "InvalidInput")
	}
	globOptions := Record{"@std/GlobOptions", map[string]Value{"patterns": libraryStrings([]string{"*"}), "exclude": libraryStrings(nil), "follow_links": false, "max_entries": int64(10), "max_results": int64(10)}}
	libraryFailure(t, fs.Operation("glob_entries").Body(RootExecution(), []Value{"", globOptions, optional("fn(entry:PathEntry)->Bool", nil, false)}), "InvalidInput")
	if data, err := os.ReadFile(sentinel); err != nil || string(data) != "keep" {
		t.Fatal("sentinel changed", err)
	}
	librarySuccess(t, fs.Operation("stat").Body(RootExecution(), []Value{".", true}))
}

func TestFileSystemRemovePreservesAbsoluteSymlinkResolution(t *testing.T) {
	parent := t.TempDir()
	base := filepath.Join(parent, "base")
	other := filepath.Join(parent, "other")
	for _, path := range []string{base, filepath.Join(other, "deep"), filepath.Join(other, "victim"), filepath.Join(base, "victim")} {
		if err := os.MkdirAll(path, 0700); err != nil {
			t.Fatal(err)
		}
	}
	if err := os.Symlink(filepath.Join(other, "deep"), filepath.Join(base, "link")); err != nil {
		t.Skipf("symlink unavailable: %v", err)
	}
	// Do not use filepath.Join: cleaning this absolute path before resolving
	// the symlink would remove the wrong victim directory.
	target := base + "/link/../victim"
	// The host decides how symlink/.. is resolved (Windows can differ).
	resolved, err := os.Stat(target)
	if err != nil {
		t.Fatal(err)
	}
	otherVictim, err := os.Stat(filepath.Join(other, "victim"))
	if err != nil {
		t.Fatal(err)
	}
	removed, preserved := filepath.Join(base, "victim"), filepath.Join(other, "victim")
	if os.SameFile(resolved, otherVictim) {
		removed, preserved = preserved, removed
	}
	fs := &libraryFileSystem{base}
	librarySuccess(t, fs.Operation("remove").Body(RootExecution(), []Value{target, true}))
	if _, err := os.Stat(removed); !os.IsNotExist(err) {
		t.Fatal("native target not removed", err)
	}
	if _, err := os.Stat(preserved); err != nil {
		t.Fatal("unrelated target removed", err)
	}
}
