package msruntime

import (
	"os"
	"path/filepath"
	"slices"
	"testing"
)

func TestGlobConsumersAgree(t *testing.T) {
	root := t.TempDir()
	files := []string{"a.txt", "b.md", ".hidden.txt", "sub/c.txt", "sub/.secret.md", "sub/deep/d.json"}
	for _, name := range files {
		path := filepath.Join(root, filepath.FromSlash(name))
		if err := os.MkdirAll(filepath.Dir(path), 0700); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(path, nil, 0600); err != nil {
			t.Fatal(err)
		}
	}
	ctx := RootExecution()
	fs := &osFileSystem{directory: root}
	for _, tt := range []struct {
		pattern string
		want    []string
	}{
		{"**/*.{txt,md}", []string{"a.txt", "b.md", "sub/c.txt"}},
		{".hidden.*", []string{".hidden.txt"}},
		{"sub/**/[cd].{txt,json}", []string{"sub/c.txt", "sub/deep/d.json"}},
		{"{a.txt,sub/c.txt}", []string{"a.txt", "sub/c.txt"}},
		{"@(a|b).+(txt|md)", []string{"a.txt", "b.md"}},
		{"sub/.*.md", []string{"sub/.secret.md"}},
	} {
		t.Run(tt.pattern, func(t *testing.T) {
			for _, name := range files {
				got := mustOK(t, Path_Posix(ctx).MatchesGlob(ctx, name, tt.pattern))
				if got != slices.Contains(tt.want, name) {
					t.Errorf("path match %q = %v", name, got)
				}
			}
			got := mustOK(t, fs.Glob(ctx, ".", tt.pattern, None[int]())).Items
			if !slices.Equal(got, tt.want) {
				t.Errorf("glob = %v, want %v", got, tt.want)
			}
			options := &GlobOptions{Patterns: NewList(tt.pattern), Exclude: NewList[string]()}
			entries := mustOK(t, fs.GlobEntries(ctx, ".", options, None[func(*Execution, *PathEntry) bool]()))
			var paths []string
			for _, entry := range entries.Items {
				paths = append(paths, entry.Path)
			}
			if !slices.Equal(paths, tt.want) {
				t.Errorf("glob_entries = %v, want %v", paths, tt.want)
			}
		})
	}
	// Every alternative must be checked before traversal, even if an earlier
	// alternative would match one of the files.
	for _, pattern := range []string{"{a.txt,[}", "@(a|b", "a\\"} {
		wantFSError(t, fs.Glob(ctx, ".", pattern, None[int]()), FileSystemError_InvalidInput{})
		options := &GlobOptions{Patterns: NewList(pattern), Exclude: NewList[string]()}
		wantFSError(t, fs.GlobEntries(ctx, ".", options, None[func(*Execution, *PathEntry) bool]()), FileSystemError_InvalidInput{})
	}
}

func TestGlobEntriesCallbackCanChangePatterns(t *testing.T) {
	root := t.TempDir()
	for _, name := range []string{"a.txt", "b.md"} {
		if err := os.WriteFile(filepath.Join(root, name), nil, 0600); err != nil {
			t.Fatal(err)
		}
	}
	ctx := RootExecution()
	fs := &osFileSystem{directory: root}
	for _, tt := range []struct {
		name     string
		includes string
		excludes string
		change   func(*GlobOptions)
	}{
		{"include", "*.txt", "*.skip", func(o *GlobOptions) { o.Patterns.Items[0] = "*.md" }},
		{"exclude", "*.*", "*.skip", func(o *GlobOptions) { o.Exclude.Items[0] = "*.txt" }},
		// Validation happens at entry. A later callback mutation retains the
		// existing matcher's behavior, including a malformed later alternative.
		{"later invalid alternative", "*.txt", "*.skip", func(o *GlobOptions) { o.Patterns.Items[0] = "*.{md,[}" }},
	} {
		t.Run(tt.name, func(t *testing.T) {
			options := &GlobOptions{Patterns: NewList(tt.includes), Exclude: NewList(tt.excludes)}
			callback := Some(func(_ *Execution, entry *PathEntry) bool {
				if entry.Path == "." {
					tt.change(options)
				}
				return false
			})
			entries := mustOK(t, fs.GlobEntries(ctx, ".", options, callback))
			if len(entries.Items) != 1 || entries.Items[0].Path != "b.md" {
				t.Fatalf("glob_entries = %v, want b.md", entries.Items)
			}
		})
	}
}
