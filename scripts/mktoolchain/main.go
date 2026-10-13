// mktoolchain trims a verified Go SDK to the tools and source references needed
// by Manuscript's runtime. Package discovery comes from Go, not a manual list.
package main

import (
	"archive/tar"
	"bytes"
	"compress/gzip"
	"encoding/json"
	"fmt"
	"github.com/manuscript-lang/manuscript/scripts/internal/devtool"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
)

func main() {
	if err := build(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

func build() error {
	if len(os.Args) != 5 {
		return fmt.Errorf("usage: mktoolchain <sdk-root> <output.tar.gz> <target-os> <target-arch>")
	}
	root, output, targetOS, targetArch := os.Args[1], os.Args[2], os.Args[3], os.Args[4]
	files := map[string]bool{}
	addDirectory := func(directory string) error {
		entries, err := os.ReadDir(filepath.Join(root, directory))
		if err != nil {
			return err
		}
		for _, entry := range entries {
			name := entry.Name()
			if entry.IsDir() || strings.HasSuffix(name, "_test.go") {
				continue
			}
			switch filepath.Ext(name) {
			case ".go", ".s", ".h", ".syso":
				files[filepath.Join(directory, name)] = true
			}
		}
		return nil
	}
	hostGo := devtool.Go()
	hostRootOutput, err := exec.Command(hostGo, "env", "GOROOT").Output()
	if err != nil {
		return fmt.Errorf("locate pinned host SDK: %w", err)
	}
	hostRoot := strings.TrimSpace(string(hostRootOutput))

	// Keep references for each supported native target, including cross builds.
	for _, target := range []string{"linux/amd64", "linux/arm64", "darwin/amd64", "darwin/arm64", "windows/amd64", "windows/arm64"} {
		parts := strings.Split(target, "/")
		command := exec.Command(hostGo, "list", "-mod=vendor", "-deps", "-json", "./pkg/runtime")
		command.Env = append(os.Environ(), "GOROOT="+hostRoot, "GOOS="+parts[0], "GOARCH="+parts[1], "CGO_ENABLED=0", "GOTOOLCHAIN=local", "GOENV=off", "GOFLAGS=")
		data, err := command.Output()
		if err != nil {
			if failure, ok := err.(*exec.ExitError); ok {
				return fmt.Errorf("discover %s runtime references: %w\n%s", target, err, failure.Stderr)
			}
			return err
		}
		decoder := json.NewDecoder(strings.NewReader(string(data)))
		for {
			var pkg struct {
				Standard   bool
				ImportPath string
				EmbedFiles []string
			}
			if err := decoder.Decode(&pkg); err == io.EOF {
				break
			} else if err != nil {
				return err
			}
			if !pkg.Standard {
				continue
			}
			directory := filepath.Join("src", filepath.FromSlash(pkg.ImportPath))
			if err := addDirectory(directory); err != nil {
				return err
			}
			for _, name := range pkg.EmbedFiles {
				files[filepath.Join(directory, name)] = true
			}
		}
	}
	for _, name := range []string{"LICENSE", "PATENTS", "VERSION", "go.env", "src/go.mod", "src/go.sum", "lib/time/zoneinfo.zip"} {
		files[filepath.FromSlash(name)] = true
	}
	extension := ""
	if targetOS == "windows" {
		extension = ".exe"
	}
	files[filepath.Join("bin", "go"+extension)] = true
	for _, tool := range []string{"compile", "link", "asm"} {
		files[filepath.Join("pkg", "tool", targetOS+"_"+targetArch, tool+extension)] = true
	}
	// Go 1.25 builds these viewers on demand. Compile them while packaging,
	// rather than shipping cmd sources or needing a tool build on first use.
	viewers, err := os.MkdirTemp("", "ms-profile-tools-")
	if err != nil {
		return err
	}
	defer os.RemoveAll(viewers)
	built := map[string]string{}
	for _, tool := range []string{"pprof", "trace"} {
		name := filepath.Join("pkg", "tool", targetOS+"_"+targetArch, tool+extension)
		output := filepath.Join(viewers, tool+extension)
		command := exec.Command(hostGo, "build", "-trimpath", "-o", output, "cmd/"+tool)
		command.Env = append(os.Environ(), "GOROOT="+hostRoot, "GOOS="+targetOS, "GOARCH="+targetArch, "CGO_ENABLED=0", "GOTOOLCHAIN=local", "GOENV=off", "GOFLAGS=", "GOWORK=off")
		if data, err := command.CombinedOutput(); err != nil {
			return fmt.Errorf("build bundled %s: %w\n%s", tool, err, data)
		}
		files[name], built[name] = true, output
	}
	if err := addDirectory("pkg/include"); err != nil {
		return err
	}
	// Runtime assembly uses these ABI headers even when CGO is disabled.
	if err := filepath.WalkDir(filepath.Join(root, "src", "runtime", "cgo"), func(name string, entry os.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if !entry.IsDir() && strings.HasSuffix(name, ".h") {
			relative, err := filepath.Rel(root, name)
			if err != nil {
				return err
			}
			files[relative] = true
		}
		return nil
	}); err != nil {
		return err
	}
	names := make([]string, 0, len(files))
	for name := range files {
		names = append(names, name)
	}
	sort.Strings(names)
	file, err := os.CreateTemp(filepath.Dir(output), ".build-payload-*.tar.gz")
	if err != nil {
		return err
	}
	defer file.Close()
	defer os.Remove(file.Name())
	compressed := gzip.NewWriter(file)
	archive := tar.NewWriter(compressed)
	var total int64
	for _, name := range names {
		source := built[name]
		if source == "" {
			source = filepath.Join(root, name)
		}
		input, err := os.Open(source)
		if err != nil {
			return err
		}
		info, err := input.Stat()
		if err != nil {
			input.Close()
			return err
		}
		if err := archive.WriteHeader(&tar.Header{Name: "go/" + filepath.ToSlash(name), Mode: int64(info.Mode().Perm()), Size: info.Size()}); err != nil {
			input.Close()
			return err
		}
		_, copyErr := io.Copy(archive, input)
		input.Close()
		if copyErr != nil {
			return copyErr
		}
		total += info.Size()
	}
	if err := archive.Close(); err != nil {
		return err
	}
	if err := compressed.Close(); err != nil {
		return err
	}
	if err := file.Close(); err != nil {
		return err
	}
	// Publish atomically: other developer checks can be embedding this file.
	// Keep an identical payload untouched so concurrent builds retain its inode.
	prepared, err := os.ReadFile(file.Name())
	if err != nil {
		return err
	}
	previous, _ := os.ReadFile(output)
	if !bytes.Equal(previous, prepared) {
		if err := os.Rename(file.Name(), output); err != nil {
			return err
		}
	}
	// Overlay selects a target payload without mutating the host payload or SDK.
	absolute, err := filepath.Abs(output)
	if err != nil {
		return err
	}
	placeholder, err := filepath.Abs(".build-payload.tar.gz")
	if err != nil {
		return err
	}
	overlay, err := json.Marshal(struct{ Replace map[string]string }{map[string]string{placeholder: absolute}})
	if err != nil {
		return err
	}
	if err := os.WriteFile(output+".overlay.json", overlay, 0644); err != nil {
		return err
	}
	fmt.Printf("Embedded build payload: %d files, %.1f MiB uncompressed\n", len(names), float64(total)/(1024*1024))
	return nil
}
