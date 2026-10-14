package build

import (
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"
)

// CacheLimit bounds the bytes of cached executables in one build cache
// directory. The bound is soft: entries used within cacheInUse are kept, and a
// file still hard-linked as a build output frees no space when evicted.
const CacheLimit = 128 << 20

const (
	// cacheInUse protects an entry another ms process may be verifying or publishing.
	cacheInUse = time.Minute
	// cacheDebris is how long an unpaired entry or staging directory is left
	// alone, since a build writes the binary before its metadata.
	cacheDebris = time.Hour
)

// touchCacheEntry marks an entry as recently used for least-recently-used
// eviction. Only the metadata moves: the executable may be hard-linked as a
// build output, whose modification time must not change.
func touchCacheEntry(metadata string) {
	now := time.Now()
	os.Chtimes(metadata, now, now)
}

type cacheEntry struct {
	binary, metadata string
	size             int64
	used             time.Time
}

// pruneBuildCache removes abandoned files, then the least recently used
// entries until the executables fit within limit. Errors are ignored: a
// failed removal only leaves the cache larger.
func pruneBuildCache(dir string, limit int64) {
	items, err := os.ReadDir(dir)
	if err != nil {
		return
	}
	entries := map[string]*cacheEntry{}
	now := time.Now()
	for _, item := range items {
		name := item.Name()
		info, err := item.Info()
		if err != nil {
			continue
		}
		path := filepath.Join(dir, name)
		idle := now.Sub(info.ModTime())
		switch {
		case item.IsDir() && strings.HasPrefix(name, ".build-"), strings.HasPrefix(name, ".manuscript-"):
			if idle > cacheDebris {
				os.RemoveAll(path)
			}
		case strings.HasSuffix(name, ".bin"), strings.HasSuffix(name, ".json"):
			id := name[:strings.LastIndexByte(name, '.')]
			entry := entries[id]
			if entry == nil {
				entry = &cacheEntry{binary: filepath.Join(dir, id+".bin"), metadata: filepath.Join(dir, id+".json")}
				entries[id] = entry
			}
			if strings.HasSuffix(name, ".bin") {
				entry.size = info.Size()
			}
			if info.ModTime().After(entry.used) {
				entry.used = info.ModTime()
			}
		}
	}
	var total int64
	var live []*cacheEntry
	for _, entry := range entries {
		_, binaryErr := os.Stat(entry.binary)
		_, metadataErr := os.Stat(entry.metadata)
		if binaryErr != nil || metadataErr != nil {
			if now.Sub(entry.used) > cacheDebris {
				os.Remove(entry.binary)
				os.Remove(entry.metadata)
			}
			continue
		}
		total += entry.size
		live = append(live, entry)
	}
	sort.Slice(live, func(i, j int) bool { return live[i].used.Before(live[j].used) })
	for _, entry := range live {
		if total <= limit || now.Sub(entry.used) < cacheInUse {
			break
		}
		os.Remove(entry.metadata)
		os.Remove(entry.binary)
		total -= entry.size
	}
}

// CleanBuildCache removes a build cache directory and reports the bytes it held.
func CleanBuildCache(dir string) (int64, error) {
	var size int64
	filepath.WalkDir(dir, func(_ string, item os.DirEntry, err error) error {
		if err == nil && item.Type().IsRegular() {
			if info, err := item.Info(); err == nil {
				size += info.Size()
			}
		}
		return nil
	})
	return size, os.RemoveAll(dir)
}
