package project_test

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/project"
)

func TestDiscoveryReportsTraversalErrors(t *testing.T) {
	root := t.TempDir()
	config := project.Project{Root: root, Source: filepath.Join(root, "missing")}
	if _, err := project.DiscoverModules(config, true); err == nil {
		t.Fatal("missing source directory was silently accepted")
	}
	blocked := filepath.Join(root, "blocked")
	if err := os.Mkdir(blocked, 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.Chmod(blocked, 0); err != nil {
		t.Skip(err)
	}
	defer os.Chmod(blocked, 0700)
	if _, err := os.ReadDir(blocked); err == nil {
		t.Skip("directory permissions not enforced")
	}
	config.Source = root
	for _, all := range []bool{false, true} {
		if _, err := project.DiscoverModules(config, all); err == nil {
			t.Fatal("unreadable directory was silently accepted")
		}
	}
}

func TestOverlayDiscoveryUsesSourceAndTestExclusions(t *testing.T) {
	p := fixture(t, manifest)
	overlay := map[string]string{}
	for _, name := range []string{"src/new.ms", "tests/new_test.ms", "src/.hidden/new.ms", "src/vendor/new.ms", "src/node_modules/new.ms", "scratch/new.ms", ".hidden/new_test.ms"} {
		overlay[filepath.Join(p.Root, name)] = ""
	}
	files, err := project.DiscoverModulesWithOverlay(p, true, overlay)
	if err != nil {
		t.Fatal(err)
	}
	if len(files) != 4 {
		t.Fatalf("overlay exclusions lost: %v", files)
	}
	for i, file := range files {
		if i > 0 && files[i-1] >= file {
			t.Fatal("discovery is not sorted:", files)
		}
	}
}
