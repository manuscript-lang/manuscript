package cli

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestCacheCleanRemovesProjectAndUserCaches(t *testing.T) {
	root, user := t.TempDir(), t.TempDir()
	t.Setenv("MANUSCRIPT_CACHE_DIR", user)
	artifacts := filepath.Join(user, "manuscript", "artifacts")
	for _, dir := range []string{filepath.Join(root, ".ms-cache"), artifacts} {
		os.MkdirAll(dir, 0o700)
		os.WriteFile(filepath.Join(dir, "x.bin"), make([]byte, 1<<20), 0o600)
	}
	status, output, errors := invoke(t, "cache", "clean", filepath.Join(root, "ms.toml"))
	if status != 0 || errors != "" || !strings.Contains(output, "Removed 2.0 MiB") {
		t.Fatalf("%d, %q, %q", status, output, errors)
	}
	for _, dir := range []string{filepath.Join(root, ".ms-cache"), artifacts} {
		if _, err := os.Stat(dir); err == nil {
			t.Errorf("%s remains", dir)
		}
	}
}

func TestCacheRequiresClean(t *testing.T) {
	if status, _, errors := invoke(t, "cache"); status != 2 || !strings.Contains(errors, "ms cache clean") {
		t.Fatal(status, errors)
	}
}
