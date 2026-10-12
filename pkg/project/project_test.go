package project_test

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/project"
)

const manifest = "[project]\nname = \"sample\"\nsource = \"src\"\nentry = \"src/main.ms\"\n"

func write(t *testing.T, root, name, source string) string {
	t.Helper()
	path := filepath.Join(root, name)
	if err := os.MkdirAll(filepath.Dir(path), 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte(source), 0600); err != nil {
		t.Fatal(err)
	}
	return path
}

func fixture(t *testing.T, source string) project.Project {
	t.Helper()
	root := t.TempDir()
	write(t, root, "src/main.ms", "")
	write(t, root, "src/value.ms", "")
	p, err := project.ReadProject(write(t, root, "ms.toml", source))
	if err != nil {
		t.Fatal(err)
	}
	return p
}

func TestManifestCanonicalPathsAndComments(t *testing.T) {
	source := strings.Replace(manifest, "sample", `sample # \"quoted\"`, 1) + "[aliases]\n\"@values\" = \"src\" # directory\n\"@one\" = \"src/value.ms\"\n"
	p := fixture(t, source)
	if p.Name != `sample # "quoted"` || p.Configuration != source || p.Source != filepath.Join(p.Root, "src") || p.Entry != filepath.Join(p.Source, "main.ms") {
		t.Fatalf("unexpected project: %+v", p)
	}
	for _, path := range []string{"./value.ms", "@values/value.ms", "@one"} {
		got, err := project.ResolveImport(p, p.Entry, path, nil)
		if err != nil || got != filepath.Join(p.Source, "value.ms") {
			t.Fatalf("%s: %s, %v", path, got, err)
		}
	}
}

func TestMalformedManifests(t *testing.T) {
	for _, tc := range []struct{ name, source, want string }{
		{"no table", "name = \"sample\"\n", "invalid manifest assignment"},
		{"missing assignment", "[project]\nname\n", "invalid manifest assignment"},
		{"unknown table", manifest + "[adapters]\n", "unsupported manifest table"},
		{"duplicate table", manifest + "[project]\n", "duplicate manifest table"},
		{"duplicate key", manifest + "name = \"other\"\n", "duplicate manifest key"},
		{"unknown key", manifest + "version = \"1\"\n", "unknown project key"},
		{"missing required key", strings.Replace(manifest, "name = \"sample\"\n", "", 1), "requires name, source, and entry"},
		{"unquoted value", strings.Replace(manifest, "\"sample\"", "sample", 1), "double-quoted"},
		{"raw Go literal", strings.Replace(manifest, "\"sample\"", "`sample`", 1), "double-quoted"},
		{"broken quote", strings.Replace(manifest, "\"sample\"", "\"sample", 1), "double-quoted"},
		{"bad escape", strings.Replace(manifest, "sample", `\q`, 1), "quoted strings"},
		{"source is file", strings.Replace(manifest, "\"src\"", "\"src/main.ms\"", 1), "existing directory"},
		{"missing source", strings.Replace(manifest, "\"src\"", "\"missing\"", 1), "missing"},
		{"entry extension", strings.Replace(manifest, "src/main.ms", "src/main.txt", 1), ".ms extension"},
		{"entry is directory", strings.Replace(manifest, "src/main.ms", "src/directory.ms", 1), "regular file"},
		{"reserved alias", manifest + "[aliases]\n\"@std\" = \"src\"\n", "invalid or reserved alias"},
		{"invalid alias", manifest + "[aliases]\n\"@2bad\" = \"src\"\n", "invalid or reserved alias"},
		{"alias chaining", manifest + "[aliases]\n\"@one\" = \"@two\"\n", "invalid or reserved alias"},
		{"duplicate alias", manifest + "[aliases]\n\"@one\" = \"src\"\n\"@one\" = \"src\"\n", "duplicate manifest key"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			root := t.TempDir()
			write(t, root, "src/main.ms", "")
			write(t, root, "src/main.txt", "")
			if err := os.Mkdir(filepath.Join(root, "src/directory.ms"), 0700); err != nil {
				t.Fatal(err)
			}
			_, err := project.ReadProject(write(t, root, "ms.toml", tc.source))
			if err == nil || !strings.Contains(err.Error(), tc.want) {
				t.Fatalf("got %v, want %q", err, tc.want)
			}
		})
	}
}

func TestImportFormsAndConfinement(t *testing.T) {
	p := fixture(t, manifest+"[aliases]\n\"@dir\" = \"src\"\n\"@file\" = \"src/value.ms\"\n")
	for _, path := range []string{"value.ms", "/value.ms", `./dir\value.ms`, "./value", "@missing/value.ms", "@dir_extra/value.ms", "@dir", "@dir/value", "@file/suffix.ms", "@std/value.ms"} {
		t.Run(path, func(t *testing.T) {
			if _, err := project.ResolveImport(p, p.Entry, path, nil); err == nil {
				t.Fatal("accepted invalid import")
			}
		})
	}
	outside := write(t, t.TempDir(), "outside.ms", "")
	rel, err := filepath.Rel(p.Source, outside)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := project.ResolveImport(p, p.Entry, filepath.ToSlash(rel), nil); err == nil || !strings.Contains(err.Error(), "escapes project root") {
		t.Fatalf("accepted escape: %v", err)
	}
	for _, key := range []string{"source", "entry", "@escape"} {
		source := manifest
		if key == "@escape" {
			source += "[aliases]\n\"@escape\" = \"" + filepath.ToSlash(outside) + "\"\n"
		} else {
			old := "src"
			if key == "entry" {
				old = "src/main.ms"
			}
			source = strings.Replace(source, key+" = \""+old+"\"", key+" = \""+filepath.ToSlash(outside)+"\"", 1)
		}
		if _, err := project.ReadProject(write(t, p.Root, "ms.toml", source)); err == nil || !strings.Contains(err.Error(), "escapes project root") {
			t.Fatalf("%s: accepted manifest escape: %v", key, err)
		}
	}
}

func TestUnsavedSourcePaths(t *testing.T) {
	p := fixture(t, manifest)
	newFile := filepath.Join(p.Source, "new.ms")
	if _, err := project.SourcePath(p.Root, newFile, nil); err == nil {
		t.Fatal("accepted missing source without overlay")
	}
	if got, err := project.SourcePath(p.Root, newFile, map[string]string{newFile: ""}); err != nil || got != newFile {
		t.Fatalf("new editor module: %s, %v", got, err)
	}
	missingParent := filepath.Join(p.Root, "missing", "new.ms")
	if _, err := project.SourcePath(p.Root, missingParent, map[string]string{missingParent: ""}); err == nil {
		t.Fatal("accepted nonexistent parent")
	}
	outside := filepath.Join(t.TempDir(), "new.ms")
	if _, err := project.SourcePath(p.Root, outside, map[string]string{outside: ""}); err == nil {
		t.Fatal("accepted outside overlay")
	}
}

func TestSymlinkSourceIdentity(t *testing.T) {
	p := fixture(t, manifest)
	link := filepath.Join(p.Source, "link.ms")
	if err := os.Symlink(filepath.Join(p.Source, "value.ms"), link); err != nil {
		t.Skipf("symlinks unavailable: %v", err)
	}
	got, err := project.SourcePath(p.Root, link, nil)
	if err != nil || got != filepath.Join(p.Source, "value.ms") {
		t.Fatalf("lost canonical identity: %s, %v", got, err)
	}
	outside := t.TempDir()
	for _, name := range []string{"existing.ms", "unsaved.ms"} {
		if name == "existing.ms" {
			write(t, outside, name, "")
		}
		link := filepath.Join(p.Source, name)
		if err := os.Symlink(filepath.Join(outside, name), link); err != nil {
			t.Fatal(err)
		}
		if _, err := project.SourcePath(p.Root, link, map[string]string{link: ""}); err == nil {
			t.Fatal("overlay hid a symlink escape")
		}
	}
	parent := filepath.Join(p.Root, "linked")
	if err := os.Symlink(outside, parent); err != nil {
		t.Fatal(err)
	}
	newFile := filepath.Join(parent, "new.ms")
	if _, err := project.SourcePath(p.Root, newFile, map[string]string{newFile: ""}); err == nil {
		t.Fatal("overlay escaped through its parent")
	}
}

func TestManifestDiscoveryKeepsTheClosestProject(t *testing.T) {
	root := t.TempDir()
	outer := write(t, root, "ms.toml", manifest)
	file := write(t, root, "nested/src/main.ms", "")
	if found, ok := project.FindManifest(file); !ok || found != outer {
		t.Fatalf("outer project not found: %s, %v", found, ok)
	}
	inner := write(t, root, "nested/ms.toml", "invalid configuration")
	if found, ok := project.FindManifest(file); !ok || found != inner {
		t.Fatalf("invalid nested project silently used its parent: %s, %v", found, ok)
	}
}
