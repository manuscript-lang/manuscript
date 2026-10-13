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
