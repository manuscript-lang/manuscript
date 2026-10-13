package project_test

import (
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/project"
)

func TestLibraryEntryIsOmittedNotDefaulted(t *testing.T) {
	source := strings.Replace(manifest, "entry = \"src/main.ms\"\n", "", 1)
	p := fixture(t, source)
	if p.Entry != "" || p.Source != filepath.Join(p.Root, "src") {
		t.Fatalf("library acquired an entry: %+v", p)
	}
	for _, entry := range []string{"", "src", "src/missing.ms", "../outside.ms"} {
		_, err := project.ReadProject(write(t, p.Root, "ms.toml", source+"entry = \""+entry+"\"\n"))
		var located *project.ManifestError
		if !errors.As(err, &located) || located.Location.Line != 4 || located.Location.Column != 9 {
			t.Fatalf("explicit bad entry %q: %v", entry, err)
		}
	}
}

func TestAliasDiagnosticKeyAndValueLocations(t *testing.T) {
	prefix := "\ufeff# café\r\n  [project]\r\nname = \"library\"\r\nsource = \"src\"\r\n[aliases]\r\n"
	for _, tc := range []struct {
		line, token string
		column      int
	}{
		{"  \"@std\" = \"src\" # invalid key\r\n", "\"@std\"", 3},
		{"  \"@bad\" = \"@other\" # invalid value\r\n", "\"@other\"", 12},
		{"  \"@bad\" = \"missing\" # unresolved target\r\n", "\"missing\"", 12},
		{"  \"@bad\" = \"src\"\r\n  \"@bad\" = \"src\"\r\n", "\"@bad\"", 3},
	} {
		t.Run(tc.token+tc.line, func(t *testing.T) {
			root := t.TempDir()
			write(t, root, "src/value.ms", "")
			source := prefix + tc.line
			_, err := project.ReadProject(write(t, root, "ms.toml", source))
			var located *project.ManifestError
			line := 6
			offset := strings.Index(source, tc.token)
			if strings.Count(tc.line, "\n") == 2 {
				line = 7
				offset = strings.LastIndex(source, tc.token)
			}
			if !errors.As(err, &located) || located.Location.File != "ms.toml" || located.Location.Line != line || located.Location.Column != tc.column || located.Location.Offset != offset {
				t.Fatalf("incorrect location: %+v, %v, want %d:%d offset %d", located, err, line, tc.column, offset)
			}
		})
	}
}

func TestAliasValidationIsSortedAndConfined(t *testing.T) {
	root := t.TempDir()
	write(t, root, "src/value.ms", "")
	outside := write(t, t.TempDir(), "value.ms", "")
	rel, err := filepath.Rel(root, outside)
	if err != nil {
		t.Fatal(err)
	}
	prefix := "[project]\nname = \"library\"\nsource = \"src\"\n[aliases]\n"
	source := prefix + "\"@z\" = \"missing\"\n  \"@a\" = \"" + filepath.ToSlash(rel) + "\"\n"
	for range 20 {
		_, err := project.ReadProject(write(t, root, "ms.toml", source))
		var located *project.ManifestError
		if !errors.As(err, &located) || located.Location.Line != 6 || located.Location.Column != 10 || !strings.Contains(err.Error(), "escapes project root") || !strings.Contains(err.Error(), "copy the sources inside this project root") {
			t.Fatalf("unordered or unrestricted validation: %v", err)
		}
	}
	link := filepath.Join(root, "src", "external")
	if err := os.Symlink(filepath.Dir(outside), link); err != nil {
		t.Skip(err)
	}
	_, err = project.ReadProject(write(t, root, "ms.toml", prefix+"\"@a\" = \"src/external\"\n"))
	var located *project.ManifestError
	if !errors.As(err, &located) || located.Location.Line != 5 || located.Location.Column != 8 || !strings.Contains(err.Error(), "escapes project root") {
		t.Fatalf("symlink alias accepted or misplaced: %v", err)
	}
}

func TestExplicitEntryKeepsCanonicalSymlinkExtension(t *testing.T) {
	p := fixture(t, manifest)
	if err := os.Symlink(p.Entry, filepath.Join(p.Root, "launcher")); err != nil {
		t.Skip(err)
	}
	source := strings.Replace(manifest, "src/main.ms", "launcher", 1)
	got, err := project.ReadProject(write(t, p.Root, "ms.toml", source))
	if err != nil || got.Entry != p.Entry {
		t.Fatalf("existing explicit entry changed: %+v %v", got, err)
	}
}
