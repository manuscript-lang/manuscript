package build

import (
	"fmt"
	support "github.com/manuscript-lang/manuscript"
	"github.com/manuscript-lang/manuscript/pkg/compiler"
	msruntime "github.com/manuscript-lang/manuscript/pkg/runtime"
	"io/fs"
	"os"
	"path/filepath"
	"strings"
	"time"
)

// A native workspace is an immutable Go module holding the embedded runtime
// and vendored dependencies. Builds share it instead of rewriting the
// dependency tree into a fresh directory, and its stable paths let Go's
// package cache reuse the runtime for every build level, including Debug.

// Application directories outlive their build only so that concurrent
// identical builds cannot remove each other's input.
const applicationRetention = time.Hour

const workspaceModule = "github.com/manuscript-lang/manuscript"

func workspaceIdentity() string {
	return bundleDigest([]struct {
		name  string
		files fs.FS
	}{{"runtime", msruntime.Sources}, {"dependencies", support.NativeDependencies}})
}

func workspaceRoot() (string, error) {
	cache, err := userCacheRoot()
	if err != nil {
		cache = filepath.Join(os.TempDir(), "manuscript-cache")
	}
	// Validation reads one marker, so a removed workspace is rebuilt even
	// within a long-lived process such as the language server.
	return materializeWorkspace(filepath.Join(cache, "manuscript", "workspaces"))
}

// Publish only a complete workspace; the first atomic rename wins and every
// process then uses the same immutable directory.
func materializeWorkspace(cache string) (string, error) {
	identity := workspaceIdentity()
	directory := filepath.Join(cache, identity[:32])
	valid := func() bool {
		marker, err := os.ReadFile(filepath.Join(directory, "ready"))
		return err == nil && string(marker) == identity
	}
	if valid() {
		return directory, nil
	}
	if err := os.MkdirAll(cache, 0700); err != nil {
		return "", err
	}
	staging, err := os.MkdirTemp(cache, ".stage-")
	if err != nil {
		return "", err
	}
	defer os.RemoveAll(staging)
	if err := writeWorkspace(staging); err != nil {
		return "", err
	}
	if err := os.WriteFile(filepath.Join(staging, "ready"), []byte(identity), 0600); err != nil {
		return "", err
	}
	if err := os.Rename(staging, directory); err != nil {
		if valid() {
			return directory, nil
		}
		return "", fmt.Errorf("publish native workspace (remove %s if incomplete): %w", directory, err)
	}
	return directory, nil
}

func writeWorkspace(dir string) error {
	if err := fs.WalkDir(support.NativeDependencies, ".", func(path string, entry fs.DirEntry, err error) error {
		if err != nil || path == "." {
			return err
		}
		target := filepath.Join(dir, filepath.FromSlash(path))
		if entry.IsDir() {
			return os.MkdirAll(target, 0755)
		}
		data, err := support.NativeDependencies.ReadFile(path)
		if err != nil {
			return err
		}
		return os.WriteFile(target, data, 0644)
	}); err != nil {
		return err
	}
	// Keep the runtime in its own compilation unit. Merging it into main (as
	// emit does) forces Go to recompile every host service on application edits.
	runtimeDir := filepath.Join(dir, "pkg", "runtime")
	if err := os.MkdirAll(runtimeDir, 0755); err != nil {
		return err
	}
	entries, err := msruntime.Sources.ReadDir(".")
	if err != nil {
		return err
	}
	for _, entry := range entries {
		data, err := msruntime.Sources.ReadFile(entry.Name())
		if err != nil {
			return err
		}
		if err := os.WriteFile(filepath.Join(runtimeDir, entry.Name()), data, 0644); err != nil {
			return err
		}
	}
	return os.MkdirAll(filepath.Join(dir, "apps"), 0755)
}

// applicationDir places generated source in a package named by its content,
// so identical builds produce the same package path and concurrent builds of
// different programs never share a directory.
func applicationDir(root, source string, kind compiler.BuildType, tags []string) (string, error) {
	apps := filepath.Join(root, "apps")
	removeExpiredApplications(apps)
	dir := filepath.Join(apps, digest([]byte(string(kind) + "\x00" + strings.Join(tags, ",") + "\x00" + source))[:32])
	if err := os.MkdirAll(dir, 0755); err != nil {
		return "", err
	}
	now := time.Now()
	if err := os.Chtimes(dir, now, now); err != nil {
		return "", err
	}
	if err := replaceFile(filepath.Join(dir, "main.go"), []byte(source), 0644); err != nil {
		return "", err
	}
	return dir, nil
}

func removeExpiredApplications(apps string) {
	entries, err := os.ReadDir(apps)
	if err != nil {
		return
	}
	for _, entry := range entries {
		if info, err := entry.Info(); err == nil && time.Since(info.ModTime()) > applicationRetention {
			os.RemoveAll(filepath.Join(apps, entry.Name()))
		}
	}
}
