package project_test

import (
	"os"
	"path/filepath"
	"reflect"
	"sort"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/project"
)

func TestDiscoveryPreservesExplicitSourceRoots(t *testing.T) {
	for _, source := range []string{".", "src", ".hidden/src", "vendor/src", "node_modules/src"} {
		t.Run(source, func(t *testing.T) {
			root := t.TempDir()
			p := project.Project{Root: root, Source: filepath.Join(root, source)}
			for _, name := range []string{"value.ms", "value_test.ms", "test.ms", "nested/value.ms", ".hidden/bad_test.ms", "vendor/bad_test.ms", "node_modules/bad_test.ms"} {
				write(t, p.Source, name, "")
			}
			outsideTest := write(t, root, "other/outside_test.ms", "")
			write(t, root, "other/unrelated.ms", "")
			for _, all := range []bool{false, true} {
				want := []string{outsideTest}
				if all || source == "." || source == "src" {
					want = append(want, filepath.Join(p.Source, "test.ms"), filepath.Join(p.Source, "value_test.ms"))
				}
				if all {
					want = append(want, filepath.Join(p.Source, "value.ms"), filepath.Join(p.Source, "nested/value.ms"))
					if source == "." {
						want = append(want, filepath.Join(root, "other/unrelated.ms"))
					}
				}
				sort.Strings(want)
				for _, overlay := range []map[string]string{nil, {}, {filepath.Join(p.Source, "value_test.ms"): "changed"}} {
					got, err := project.DiscoverModulesWithOverlay(p, all, overlay)
					if err != nil || !reflect.DeepEqual(got, want) {
						t.Fatalf("all=%v overlay=%v: got %v, %v; want %v", all, overlay, got, err, want)
					}
				}
			}
		})
	}
}

func TestDiscoveryDoesNotFollowDirectorySymlinks(t *testing.T) {
	root := t.TempDir()
	write(t, root, "src/value.ms", "")
	test := write(t, root, "src/value_test.ms", "")
	if err := os.Symlink(filepath.Join(root, "src"), filepath.Join(root, "linked")); err != nil {
		t.Skip(err)
	}
	// An explicit symlink root is also a symlink entry to WalkDir; it is not
	// followed. A Project produced by ReadProject has already resolved it.
	p := project.Project{Root: root, Source: filepath.Join(root, "linked")}
	got, err := project.DiscoverModules(p, true)
	if err != nil || !reflect.DeepEqual(got, []string{test}) {
		t.Fatalf("directory symlink followed: %v, %v", got, err)
	}
	// Discovery accepts a directly constructed Project with a file source;
	// skipping a file with SkipDir would truncate the surrounding root walk.
	p.Source = write(t, root, "a.ms", "")
	got, err = project.DiscoverModules(p, true)
	if err != nil || !reflect.DeepEqual(got, []string{p.Source, test}) {
		t.Fatalf("file source truncated discovery: %v, %v", got, err)
	}
}

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
