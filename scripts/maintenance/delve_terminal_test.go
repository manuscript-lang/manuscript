package main

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestVendorRefreshPreservesTerminalLifecycle(t *testing.T) {
	root := t.TempDir()
	current := map[string][]byte{}
	for _, patch := range delveTerminalPatches {
		if _, ok := current[patch.path]; ok {
			continue
		}
		data, err := os.ReadFile(filepath.Join("..", "..", patch.path))
		if err != nil {
			t.Fatal(err)
		}
		current[patch.path] = data
	}
	for path, data := range current {
		upstream := string(data)
		for i := len(delveTerminalPatches) - 1; i >= 0; i-- {
			patch := delveTerminalPatches[i]
			if patch.path == path {
				if strings.Count(upstream, patch.after) != 1 {
					t.Fatalf("vendored lifecycle patch drifted: %s", path)
				}
				upstream = strings.Replace(upstream, patch.after, patch.before, 1)
			}
		}
		name := filepath.Join(root, path)
		if err := os.MkdirAll(filepath.Dir(name), 0755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(name, []byte(upstream), 0644); err != nil {
			t.Fatal(err)
		}
	}
	for range 2 {
		if err := patchDelveTerminal(root); err != nil {
			t.Fatal(err)
		}
		for path, want := range current {
			got, err := os.ReadFile(filepath.Join(root, path))
			if err != nil || !bytes.Equal(got, want) {
				t.Fatalf("vendor refresh changed %s: %v", path, err)
			}
		}
		for _, base := range []string{root, filepath.Join("..", "..")} {
			data, err := os.ReadFile(filepath.Join(base, "vendor/github.com/go-delve/liner/input_manuscript_test.go"))
			if err != nil || !bytes.Equal(data, linerLifecycleTest) {
				t.Fatalf("vendor prompt regression drifted: %v", err)
			}
		}
	}
}
