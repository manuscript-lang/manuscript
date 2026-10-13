package gotoolchain

import (
	"bufio"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"maps"
	"os"
	"path/filepath"
	"runtime"
	"slices"
	"strings"

	"github.com/manuscript-lang/manuscript/internal/gotoolchain/internal/buildcfg"
)

// The compile, asm, and pack steps below follow cmd/go/internal/work/gc.go
// in the copied release; compare them when updating the copy.

// archiveKey identifies a package archive by its tools, settings, sources,
// and dependency archives. Standard sources are fixed within an SDK release,
// so their size and modification time suffice; other sources are hashed.
func (b *builder) archiveKey(p *pkg) string {
	hash := sha256.New()
	arch, archValue := buildcfg.GOGOARCH()
	fmt.Fprintf(hash, "archive 1\n%s %s/%s %s=%s %q\n", Version(), buildcfg.GOOS, buildcfg.GOARCH, arch, archValue, buildcfg.ToolTags)
	fmt.Fprintf(hash, "%q %q %v\n", b.Tags, b.gcflags(), b.Trimpath)
	fmt.Fprintf(hash, "%s %s %s %v %q\n", p.path, p.dir, b.lang(p), p.standard, p.files.EmbedPatterns)
	embedded, _ := b.embedFiles(p)
	names := slices.Concat(p.files.GoFiles, p.files.SFiles, p.files.HFiles, slices.Collect(maps.Keys(embedded)))
	slices.Sort(names)
	for _, name := range names {
		file := filepath.Join(p.dir, filepath.FromSlash(name))
		if p.standard {
			if info, err := os.Stat(file); err == nil {
				fmt.Fprintf(hash, "file %s %d %d\n", name, info.Size(), info.ModTime().UnixNano())
			}
			continue
		}
		data, _ := os.ReadFile(file)
		fmt.Fprintf(hash, "file %s %x\n", name, sha256.Sum256(data))
	}
	for _, imported := range slices.Sorted(maps.Keys(p.imports)) {
		fmt.Fprintf(hash, "import %s %s\n", imported, p.imports[imported].key)
	}
	return hex.EncodeToString(hash.Sum(nil))
}

func (b *builder) gcflags() []string {
	return strings.Fields(strings.TrimPrefix(b.GCFlags, "all="))
}

// Standard packages whose declarations are completed by the runtime, which
// therefore are not compiled with -complete.
var incomplete = map[string]bool{
	"bytes": true, "internal/poll": true, "net": true, "os": true,
	"runtime/metrics": true, "runtime/pprof": true, "runtime/trace": true,
	"sync": true, "syscall": true, "time": true,
}

// compileArchive compiles p in a temporary directory beside its archive and
// publishes the archive by renaming it into place.
func (b *builder) compileArchive(p *pkg) error {
	if err := os.MkdirAll(filepath.Dir(p.archive), 0755); err != nil {
		return err
	}
	objdir, err := os.MkdirTemp(filepath.Dir(p.archive), ".build-")
	if err != nil {
		return err
	}
	defer os.RemoveAll(objdir)
	archive := filepath.Join(objdir, "_pkg_.a")
	arguments := []string{"-o", archive, "-trimpath", b.trimpath(p, objdir), "-p", p.path, "-lang=" + b.lang(p)}
	if p.standard {
		arguments = append(arguments, "-std")
	}
	assembly := len(p.files.SFiles) > 0
	if !assembly && !(p.standard && incomplete[p.path]) {
		arguments = append(arguments, "-complete")
	}
	if assembly {
		symabis, err := b.symabis(p, objdir)
		if err != nil {
			return err
		}
		arguments = append(arguments, "-symabis", symabis)
	}
	// Like the go command, use up to four backend workers while other
	// packages compile alongside, and every processor for package main.
	concurrency := runtime.GOMAXPROCS(0)
	if p.path != "main" {
		concurrency = min(concurrency, 4)
	}
	arguments = append(arguments, fmt.Sprintf("-c=%d", concurrency))
	arguments = append(arguments, b.gcflags()...)
	importcfg, err := b.writeImportConfig(p, objdir)
	if err != nil {
		return err
	}
	arguments = append(arguments, "-nolocalimports", "-importcfg", importcfg)
	if len(p.files.EmbedPatterns) > 0 {
		embedcfg, err := b.writeEmbedConfig(p, objdir)
		if err != nil {
			return err
		}
		arguments = append(arguments, "-embedcfg", embedcfg)
	}
	arguments = append(arguments, "-pack")
	if assembly {
		arguments = append(arguments, "-asmhdr", filepath.Join(objdir, "go_asm.h"))
	}
	for _, name := range p.files.GoFiles {
		arguments = append(arguments, filepath.Join(p.dir, name))
	}
	if err := run("compile", p.dir, b.toolEnvironment(), arguments...); err != nil {
		return err
	}
	var objects []string
	for _, name := range p.files.SFiles {
		object := filepath.Join(objdir, strings.TrimSuffix(name, ".s")+".o")
		arguments := append(b.asmArguments(p, objdir), "-o", object, filepath.Join(p.dir, name))
		if err := run("asm", p.dir, b.toolEnvironment(), arguments...); err != nil {
			return err
		}
		objects = append(objects, object)
	}
	if err := pack(archive, objects); err != nil {
		return err
	}
	return os.Rename(archive, p.archive)
}

// symabis writes the ABI declarations of p's assembly functions, which the
// compiler reads before go_asm.h exists.
func (b *builder) symabis(p *pkg, objdir string) (string, error) {
	if err := os.WriteFile(filepath.Join(objdir, "go_asm.h"), nil, 0644); err != nil {
		return "", err
	}
	symabis := filepath.Join(objdir, "symabis")
	arguments := append(b.asmArguments(p, objdir), "-gensymabis", "-o", symabis)
	for _, name := range p.files.SFiles {
		arguments = append(arguments, filepath.Join(p.dir, name))
	}
	return symabis, run("asm", p.dir, b.toolEnvironment(), arguments...)
}

// writeImportConfig maps each of p's imports to its archive, including the
// standard library's renamed vendor packages.
func (b *builder) writeImportConfig(p *pkg, objdir string) (string, error) {
	var config strings.Builder
	config.WriteString("# import config\n")
	for _, imported := range slices.Sorted(maps.Keys(p.imports)) {
		dependency := p.imports[imported]
		if dependency.path != imported {
			fmt.Fprintf(&config, "importmap %s=%s\n", imported, dependency.path)
		}
		fmt.Fprintf(&config, "packagefile %s=%s\n", dependency.path, dependency.archive)
	}
	file := filepath.Join(objdir, "importcfg")
	return file, os.WriteFile(file, []byte(config.String()), 0644)
}

func (b *builder) writeEmbedConfig(p *pkg, objdir string) (string, error) {
	files, patterns := b.embedFiles(p)
	data, err := json.Marshal(struct {
		Patterns map[string][]string
		Files    map[string]string
	}{patterns, files})
	if err != nil {
		return "", err
	}
	file := filepath.Join(objdir, "embedcfg")
	return file, os.WriteFile(file, data, 0644)
}

func (b *builder) asmArguments(p *pkg, objdir string) []string {
	arguments := []string{"-p", p.path, "-trimpath", b.trimpath(p, objdir), "-I", objdir, "-I", filepath.Join(b.GOROOT, "pkg", "include"),
		"-D", "GOOS_" + buildcfg.GOOS, "-D", "GOARCH_" + buildcfg.GOARCH}
	switch buildcfg.GOARCH {
	case "amd64":
		arguments = append(arguments, "-D", fmt.Sprintf("GOAMD64_v%d", buildcfg.GOAMD64))
	case "arm64":
		if buildcfg.GOARM64.LSE {
			arguments = append(arguments, "-D", "GOARM64_LSE")
		}
	}
	return arguments
}

// trimpath removes the temporary directory from recorded paths and, for
// trimmed builds, replaces source directories with import paths.
func (b *builder) trimpath(p *pkg, objdir string) string {
	rewrite := ""
	if b.Trimpath {
		target := p.path
		switch {
		case p.path == "main":
			target = b.ImportPath
		case p.module != nil:
			target = p.module.path + "@" + p.module.version + strings.TrimPrefix(p.path, p.module.path)
		}
		rewrite = p.dir + "=>" + target + ";"
	}
	return rewrite + objdir + "=>"
}

// toolEnvironment sets GOROOT for the tools; trimmed executables record none.
func (b *builder) toolEnvironment() []string {
	var environment []string
	for _, entry := range b.Environment {
		if key, _, _ := strings.Cut(entry, "="); key != "GOROOT" && key != toolVariable {
			environment = append(environment, entry)
		}
	}
	if b.Trimpath {
		return append(environment, "GOROOT=")
	}
	return append(environment, "GOROOT="+b.GOROOT)
}

// pack appends assembled objects to a compiled archive in Unix ar format.
func pack(archive string, objects []string) error {
	if len(objects) == 0 {
		return nil
	}
	file, err := os.OpenFile(archive, os.O_WRONLY|os.O_APPEND, 0)
	if err != nil {
		return err
	}
	defer file.Close()
	writer := bufio.NewWriter(file)
	for _, object := range objects {
		data, err := os.ReadFile(object)
		if err != nil {
			return err
		}
		name := filepath.Base(object)
		name = (name + strings.Repeat(" ", 16))[:16]
		fmt.Fprintf(writer, "%s%-12d%-6d%-6d%-8o%-10d`\n", name, 0, 0, 0, 0644, len(data))
		writer.Write(data)
		if len(data)%2 != 0 {
			writer.WriteByte(0)
		}
	}
	if err := writer.Flush(); err != nil {
		return err
	}
	return file.Close()
}
