package compiler

import (
	"archive/tar"
	"bytes"
	"compress/gzip"
	"fmt"
	support "github.com/manuscript-lang/manuscript"
	"io"
	"io/fs"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"sync"
)

var bundledToolchain struct {
	sync.Once
	root string
	err  error
}

func goExecutable(root string) string {
	name := "go"
	if runtime.GOOS == "windows" {
		name += ".exe"
	}
	return filepath.Join(root, "bin", name)
}

func validateToolchain(root string) error {
	files := []string{goExecutable(root), filepath.Join(root, "VERSION"), filepath.Join(root, "src", "runtime", "runtime.go")}
	for _, tool := range []string{"compile", "link", "asm"} {
		if runtime.GOOS == "windows" {
			tool += ".exe"
		}
		files = append(files, filepath.Join(root, "pkg", "tool", runtime.GOOS+"_"+runtime.GOARCH, tool))
	}
	for _, name := range files {
		info, err := os.Stat(name)
		if err != nil {
			return err
		}
		if !info.Mode().IsRegular() {
			return fmt.Errorf("invalid toolchain file: %s", name)
		}
	}
	return nil
}

func bundledGoRoot() (string, error) {
	bundledToolchain.Do(func() {
		cache := os.Getenv("MANUSCRIPT_CACHE_DIR")
		if cache == "" {
			var err error
			cache, err = os.UserCacheDir()
			if err != nil {
				bundledToolchain.err = err
				return
			}
		}
		absolute, err := filepath.Abs(cache)
		if err != nil {
			bundledToolchain.err = err
			return
		}
		bundledToolchain.root, bundledToolchain.err = materializeToolchain(support.GoToolchainArchive, filepath.Join(absolute, "manuscript", "toolchains"))
	})
	return bundledToolchain.root, bundledToolchain.err
}

// Publish only a complete build payload. Concurrent ms processes can extract independently;
// the first atomic rename wins and all processes use the same immutable directory.
func materializeToolchain(archive []byte, cache string) (string, error) {
	identity := digest(archive)
	directory := filepath.Join(cache, identity)
	root := filepath.Join(directory, "go")
	valid := func() bool {
		marker, err := os.ReadFile(filepath.Join(directory, "ready"))
		if err != nil || string(marker) != identity {
			return false
		}
		return validateToolchain(root) == nil
	}
	if valid() {
		return root, nil
	}
	if err := os.MkdirAll(cache, 0700); err != nil {
		return "", err
	}
	staging, err := os.MkdirTemp(cache, ".extract-")
	if err != nil {
		return "", err
	}
	defer os.RemoveAll(staging)
	if err := extractToolchain(archive, staging); err != nil {
		return "", err
	}
	if err := validateToolchain(filepath.Join(staging, "go")); err != nil {
		return "", fmt.Errorf("incomplete bundled build payload: %w", err)
	}
	if err := os.WriteFile(filepath.Join(staging, "ready"), []byte(identity), 0600); err != nil {
		return "", err
	}
	if err := os.Rename(staging, directory); err != nil {
		if valid() {
			return root, nil
		}
		return "", fmt.Errorf("publish toolchain cache (remove %s if incomplete): %w", directory, err)
	}
	return root, nil
}

func extractToolchain(archive []byte, destination string) error {
	write := func(name string, mode fs.FileMode, reader io.Reader) error {
		name = strings.TrimSuffix(name, "/")
		if !fs.ValidPath(name) || strings.ContainsAny(name, "\\:") || name != "go" && !strings.HasPrefix(name, "go/") {
			return fmt.Errorf("invalid bundled archive path: %q", name)
		}
		target := filepath.Join(destination, filepath.FromSlash(name))
		if mode.IsDir() {
			return os.MkdirAll(target, 0755)
		}
		if !mode.IsRegular() {
			return fmt.Errorf("unsupported bundled archive entry: %q", name)
		}
		if err := os.MkdirAll(filepath.Dir(target), 0755); err != nil {
			return err
		}
		file, err := os.OpenFile(target, os.O_WRONLY|os.O_CREATE|os.O_EXCL, mode.Perm())
		if err != nil {
			return err
		}
		_, copyErr := io.Copy(file, reader)
		closeErr := file.Close()
		if copyErr != nil {
			return copyErr
		}
		return closeErr
	}
	compressed, err := gzip.NewReader(bytes.NewReader(archive))
	if err != nil {
		return err
	}
	defer compressed.Close()
	reader := tar.NewReader(compressed)
	for {
		entry, err := reader.Next()
		if err == io.EOF {
			// Tar EOF can precede the gzip trailer. Validate truncation and checksum before publication.
			_, err := io.Copy(io.Discard, compressed)
			return err
		}
		if err != nil {
			return err
		}
		if err := write(entry.Name, entry.FileInfo().Mode(), reader); err != nil {
			return err
		}
	}
}
