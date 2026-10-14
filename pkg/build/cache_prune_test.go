package build

import (
	"os"
	"path/filepath"
	"testing"
	"time"
)

func writeEntry(t *testing.T, dir, id string, size int, age time.Duration) {
	t.Helper()
	when := time.Now().Add(-age)
	for name, data := range map[string][]byte{id + ".bin": make([]byte, size), id + ".json": []byte("{}")} {
		path := filepath.Join(dir, name)
		if err := os.WriteFile(path, data, 0600); err != nil {
			t.Fatal(err)
		}
		os.Chtimes(path, when, when)
	}
}

func exists(path string) bool { _, err := os.Stat(path); return err == nil }

func TestPruneEvictsLeastRecentlyUsedOverLimit(t *testing.T) {
	dir := t.TempDir()
	writeEntry(t, dir, "old", 100, 3*time.Hour)
	writeEntry(t, dir, "mid", 100, 2*time.Hour)
	writeEntry(t, dir, "new", 100, 10*time.Minute)
	writeEntry(t, dir, "fresh", 100, 0)
	pruneBuildCache(dir, 250)
	for id, want := range map[string]bool{"old": false, "mid": false, "new": true, "fresh": true} {
		if exists(filepath.Join(dir, id+".bin")) != want || exists(filepath.Join(dir, id+".json")) != want {
			t.Errorf("%s kept = %v, want %v", id, !want, want)
		}
	}
}

func TestPruneKeepsEntriesInUseEvenOverLimit(t *testing.T) {
	dir := t.TempDir()
	writeEntry(t, dir, "a", 100, 0)
	writeEntry(t, dir, "b", 100, 0)
	pruneBuildCache(dir, 1)
	if !exists(filepath.Join(dir, "a.bin")) || !exists(filepath.Join(dir, "b.bin")) {
		t.Fatal("evicted an entry used within the last minute")
	}
}

func TestPruneRemovesOnlyAbandonedDebris(t *testing.T) {
	dir := t.TempDir()
	staleStage := filepath.Join(dir, ".build-stale")
	freshStage := filepath.Join(dir, ".build-fresh")
	for _, d := range []string{staleStage, freshStage} {
		os.Mkdir(d, 0700)
	}
	old := time.Now().Add(-2 * time.Hour)
	os.Chtimes(staleStage, old, old)
	// An unpaired binary belongs to a build between its two writes.
	os.WriteFile(filepath.Join(dir, "building.bin"), []byte("x"), 0600)
	os.WriteFile(filepath.Join(dir, "dead.bin"), []byte("x"), 0600)
	os.Chtimes(filepath.Join(dir, "dead.bin"), old, old)
	pruneBuildCache(dir, 1<<30)
	if exists(staleStage) || !exists(freshStage) || !exists(filepath.Join(dir, "building.bin")) || exists(filepath.Join(dir, "dead.bin")) {
		t.Fatal("debris handling wrong")
	}
}

func TestCleanBuildCacheReportsBytes(t *testing.T) {
	dir := filepath.Join(t.TempDir(), ".ms-cache")
	os.Mkdir(dir, 0700)
	os.WriteFile(filepath.Join(dir, "a.bin"), make([]byte, 10), 0600)
	size, err := CleanBuildCache(dir)
	if err != nil || size != 10 || exists(dir) {
		t.Fatal(size, err)
	}
	if _, err := CleanBuildCache(dir); err != nil {
		t.Fatal(err)
	}
}
