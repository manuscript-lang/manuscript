package compiler

import (
	"archive/tar"
	"bytes"
	"compress/gzip"
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"sync"
	"testing"
)

func TestNativeToolchainEnvironment(t *testing.T) {
	tool := filepath.Join(t.TempDir(), "custom-go")
	t.Setenv("MANUSCRIPT_GO", tool)
	t.Setenv("GOROOT", "/custom-root")
	t.Setenv("CGO_ENABLED", "1")
	t.Setenv("GOTOOLCHAIN", "auto")
	t.Setenv("GOENV", "/host-settings")
	t.Setenv("GOFLAGS", "-race")
	command, err := goCommand("env")
	if err != nil || command.Path != tool {
		t.Fatalf("explicit selection failed: %v, %v", command, err)
	}
	for key, value := range map[string]string{"GOROOT": "/custom-root", "CGO_ENABLED": "0", "GOTOOLCHAIN": "local", "GOENV": "off", "GOFLAGS": "-race"} {
		count := 0
		for _, entry := range command.Env {
			if strings.HasPrefix(entry, key+"=") {
				count++
				if entry != key+"="+value {
					t.Errorf("unexpected setting: %s", entry)
				}
			}
		}
		if count != 1 {
			t.Errorf("%s appears %d times", key, count)
		}
	}
}

func testArchive(t *testing.T, files map[string]string) []byte {
	t.Helper()
	var buffer bytes.Buffer
	compressed := gzip.NewWriter(&buffer)
	archive := tar.NewWriter(compressed)
	for name, data := range files {
		if err := archive.WriteHeader(&tar.Header{Name: name, Mode: 0755, Size: int64(len(data))}); err != nil {
			t.Fatal(err)
		}
		if _, err := archive.Write([]byte(data)); err != nil {
			t.Fatal(err)
		}
	}
	if err := archive.Close(); err != nil {
		t.Fatal(err)
	}
	if err := compressed.Close(); err != nil {
		t.Fatal(err)
	}
	return buffer.Bytes()
}

func TestToolchainCacheConcurrentPublicationAndReuse(t *testing.T) {
	archive := completeToolchainArchive(t)
	cache := t.TempDir()
	var workers sync.WaitGroup
	for range 8 {
		workers.Add(1)
		go func() {
			defer workers.Done()
			if _, err := materializeToolchain(archive, cache); err != nil {
				t.Error(err)
			}
		}()
	}
	workers.Wait()
	root, err := materializeToolchain(archive, cache)
	if err != nil {
		t.Fatal(err)
	}
	first, err := os.Stat(goExecutable(root))
	if err != nil {
		t.Fatal(err)
	}
	if data, err := os.ReadFile(goExecutable(root)); err != nil || string(data) != "compiler" {
		t.Fatalf("incomplete extraction: %q, %v", data, err)
	}
	secondRoot, err := materializeToolchain(archive, cache)
	if err != nil || secondRoot != root {
		t.Fatalf("cache not reused: %s, %v", secondRoot, err)
	}
	second, _ := os.Stat(goExecutable(root))
	if first.ModTime() != second.ModTime() {
		t.Fatal("cached toolchain was rewritten")
	}
	entries, err := os.ReadDir(cache)
	if err != nil || len(entries) != 1 {
		t.Fatalf("extraction directories leaked: %v, %v", entries, err)
	}
}

func TestToolchainArchiveCannotEscapeCache(t *testing.T) {
	for _, name := range []string{"../outside", "go/../../outside", "/outside", "go/C:\\outside"} {
		t.Run(name, func(t *testing.T) {
			cache := t.TempDir()
			if _, err := materializeToolchain(testArchive(t, map[string]string{name: "invalid"}), cache); err == nil {
				t.Fatal("accepted escaping archive")
			}
			entries, err := os.ReadDir(cache)
			if err != nil || len(entries) != 0 {
				t.Fatalf("failed extraction published a cache: %v, %v", entries, err)
			}
		})
	}
}

func TestIncompleteToolchainNotPublished(t *testing.T) {
	cache := t.TempDir()
	if _, err := materializeToolchain(testArchive(t, map[string]string{"go/VERSION": "go1.25.1"}), cache); err == nil {
		t.Fatal("published incomplete toolchain")
	}
	entries, err := os.ReadDir(cache)
	if err != nil || len(entries) != 0 {
		t.Fatalf("failed extraction leaked a cache: %v, %v", entries, err)
	}
}

func completeToolchainArchive(t *testing.T) []byte {
	t.Helper()
	name := "go/bin/go"
	if runtime.GOOS == "windows" {
		name += ".exe"
	}
	files := map[string]string{name: "compiler", "go/VERSION": "go1.25.1", "go/src/runtime/runtime.go": "package runtime"}
	for _, tool := range []string{"compile", "link", "asm"} {
		if runtime.GOOS == "windows" {
			tool += ".exe"
		}
		files["go/pkg/tool/"+runtime.GOOS+"_"+runtime.GOARCH+"/"+tool] = "tool"
	}
	return testArchive(t, files)
}

func TestTruncatedToolchainNeverPublishesAndCanRetry(t *testing.T) {
	archive := completeToolchainArchive(t)
	for _, missing := range []int{1, 8, 16, len(archive) / 2} {
		t.Run(fmt.Sprint(missing), func(t *testing.T) {
			cache := t.TempDir()
			if _, err := materializeToolchain(archive[:len(archive)-missing], cache); err == nil {
				t.Fatal("published an interrupted archive")
			}
			entries, err := os.ReadDir(cache)
			if err != nil || len(entries) != 0 {
				t.Fatalf("failed extraction leaked files: %v, %v", entries, err)
			}
			if _, err := materializeToolchain(archive, cache); err != nil {
				t.Fatalf("valid retry failed: %v", err)
			}
		})
	}
}
