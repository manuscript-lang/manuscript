package compiler

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	support "github.com/manuscript-lang/manuscript"
	"github.com/manuscript-lang/manuscript/checker"
	"github.com/manuscript-lang/manuscript/lexer"
	"github.com/manuscript-lang/manuscript/parser"
	"github.com/manuscript-lang/manuscript/project"
	msruntime "github.com/manuscript-lang/manuscript/runtime"
	"github.com/manuscript-lang/manuscript/stdlib"
	"github.com/manuscript-lang/manuscript/syntax"
	"io"
	"io/fs"
	"os"
	"path/filepath"
	"reflect"
	"sort"
	"strings"
)

type BuildPin struct {
	Format               int               `json:"format"`
	Compiler             string            `json:"compiler"`
	ImplementationSHA256 string            `json:"implementation_sha256"`
	Toolchain            map[string]string `json:"toolchain"`
}
type BuildMetadata struct {
	BuildPin
	BuildID             string            `json:"build_id"`
	Sources             map[string]string `json:"sources"`
	ConfigurationSHA256 string            `json:"configuration_sha256"`
	ExecutableSHA256    string            `json:"executable_sha256"`
	SourceRoot          string            `json:"source_root,omitempty"`
	Debug               bool              `json:"debug"`
}

func digest(data []byte) string { sum := sha256.Sum256(data); return hex.EncodeToString(sum[:]) }
func implementationDigest() string {
	bundles := []struct {
		name  string
		files fs.FS
	}{{"lexer", lexer.ImplementationSources}, {"parser", parser.ImplementationSources}, {"checker", checker.ImplementationSources}, {"syntax", syntax.ImplementationSources}, {"project", project.ImplementationSources}, {"compiler", ImplementationSources}, {"runtime", msruntime.Sources}, {"dependencies", support.NativeDependencies}, {"stdlib", stdlib.Sources}}
	var data strings.Builder
	for _, bundle := range bundles {

		fs.WalkDir(bundle.files, ".", func(path string, entry fs.DirEntry, err error) error {
			if err != nil {
				return err
			}
			if entry.IsDir() || strings.HasSuffix(path, "_test.go") {
				return nil
			}
			contents, err := fs.ReadFile(bundle.files, path)
			if err != nil {
				return err
			}
			data.WriteString(bundle.name + "/" + path + "\x00" + digest(contents) + "\n")
			return nil
		})

	}
	return digest([]byte(data.String()))
}
func CurrentPin() (BuildPin, error) {
	command, err := goCommand("env", "-json", "GOVERSION", "GOOS", "GOARCH", "CGO_ENABLED", "GOEXPERIMENT", "GOFLAGS", "GOAMD64", "GOARM", "GOARM64", "GOMIPS", "GOMIPS64", "GOPPC64", "GORISCV64", "GOWASM")
	if err != nil {
		return BuildPin{}, err
	}
	data, err := command.CombinedOutput()
	if err != nil {
		return BuildPin{}, fmt.Errorf("read Go toolchain: %w: %s", err, data)
	}
	var toolchain map[string]string
	if err := json.Unmarshal(data, &toolchain); err != nil {
		return BuildPin{}, err
	}
	if toolchain["GOFLAGS"] != "" {
		return BuildPin{}, fmt.Errorf("pinned builds require empty GOFLAGS; use the explicit debug build option")
	}
	return BuildPin{1, support.Version(), implementationDigest(), toolchain}, nil
}
func WritePin(root string) error {
	pin, err := CurrentPin()
	if err != nil {
		return err
	}
	data, err := json.MarshalIndent(pin, "", "  ")
	if err != nil {
		return err
	}
	return atomicWrite(filepath.Join(root, "ms.lock"), append(data, '\n'), 0644)
}
func readPin(root string) (BuildPin, error) {
	data, err := os.ReadFile(filepath.Join(root, "ms.lock"))
	if err != nil {
		return BuildPin{}, fmt.Errorf("project build requires ms.lock; run ms lock %s: %w", filepath.Join(root, "ms.toml"), err)
	}
	var pin BuildPin
	decoder := json.NewDecoder(strings.NewReader(string(data)))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&pin); err != nil {
		return BuildPin{}, fmt.Errorf("invalid ms.lock: %w", err)
	}
	if err := decoder.Decode(new(any)); err != io.EOF {
		return BuildPin{}, fmt.Errorf("ms.lock must contain exactly one JSON object")
	}
	return pin, nil
}

func CheckPin(root string) error {
	expected, err := readPin(root)
	if err != nil {
		return err
	}
	actual, err := CurrentPin()
	if err != nil {
		return err
	}
	return comparePin(root, expected, actual)
}

func comparePin(root string, expected, actual BuildPin) error {
	if !reflect.DeepEqual(expected, actual) {
		return fmt.Errorf("ms.lock does not match compiler/runtime, Go toolchain, or target; run ms lock %s to explicitly update", filepath.Join(root, "ms.toml"))
	}
	return nil
}

func atomicWrite(filename string, data []byte, mode os.FileMode) error {
	existing, err := os.ReadFile(filename)
	if err == nil && digest(existing) == digest(data) {
		return os.Chmod(filename, mode)
	}
	file, err := os.CreateTemp(filepath.Dir(filename), ".manuscript-write-*")
	if err != nil {
		return err
	}
	name := file.Name()
	defer os.Remove(name)
	if _, err := file.Write(data); err != nil {
		file.Close()
		return err
	}
	if err := file.Chmod(mode); err != nil {
		file.Close()
		return err
	}
	if err := file.Sync(); err != nil {
		file.Close()
		return err
	}
	if err := file.Close(); err != nil {
		return err
	}
	return os.Rename(name, filename)
}

// BuildChecked caches only verified native artifacts. Parsing/checking still precedes it.
func BuildChecked(result Result, output, cacheDir string, debug bool) (BuildMetadata, error) {
	if !result.Success() || result.Program == nil || result.Source == "" {
		return BuildMetadata{}, fmt.Errorf("cannot build a program with diagnostics")
	}
	var expected BuildPin
	if result.ProjectRoot != "" {
		var err error
		expected, err = readPin(result.ProjectRoot)
		if err != nil {
			return BuildMetadata{}, err
		}
	}
	pin, err := CurrentPin()
	if err != nil {
		return BuildMetadata{}, err
	}
	if result.ProjectRoot != "" {
		if err := comparePin(result.ProjectRoot, expected, pin); err != nil {
			return BuildMetadata{}, err
		}
	}
	metadata := BuildMetadata{BuildPin: pin, Sources: map[string]string{}, ConfigurationSHA256: digest([]byte(result.Configuration)), Debug: debug}
	if result.ProjectRoot != "" {
		metadata.Sources["ms.toml"] = digest([]byte(result.Configuration))
	}
	for _, module := range result.Program.Modules {
		metadata.Sources[module.File] = digest([]byte(module.Source))
	}
	source := result.Source
	if debug {
		source = debugSource(result)
		metadata.SourceRoot = result.SourceRoot
	}
	identity, _ := json.Marshal(struct {
		Metadata        BuildMetadata
		GeneratedSHA256 string
	}{metadata, digest([]byte(source))})
	metadata.BuildID = digest(identity)
	cacheBinary, cacheMetadata := "", ""
	if cacheDir != "" {
		if err := os.MkdirAll(cacheDir, 0700); err != nil {
			return metadata, err
		}
		cacheBinary = filepath.Join(cacheDir, metadata.BuildID+".bin")
		cacheMetadata = filepath.Join(cacheDir, metadata.BuildID+".json")
		info, readErr := os.ReadFile(cacheMetadata)
		if readErr == nil {
			var cached BuildMetadata
			binary, binaryErr := os.ReadFile(cacheBinary)
			if json.Unmarshal(info, &cached) == nil && cached.BuildID == metadata.BuildID && binaryErr == nil && digest(binary) == cached.ExecutableSHA256 {
				expected := metadata
				expected.ExecutableSHA256 = cached.ExecutableSHA256
				if reflect.DeepEqual(expected, cached) {
					if err := atomicWrite(output, binary, 0755); err != nil {
						return metadata, err
					}
					return cached, writeBuildMetadata(output, cached)
				}
			}
		}
	}
	if err := buildNative(source, output, debug); err != nil {
		return metadata, err
	}
	binary, err := os.ReadFile(output)
	if err != nil {
		return metadata, err
	}
	metadata.ExecutableSHA256 = digest(binary)
	if cacheDir != "" {
		if err := atomicWrite(cacheBinary, binary, 0755); err != nil {
			return metadata, err
		}
		data, _ := json.Marshal(metadata)
		if err := atomicWrite(cacheMetadata, data, 0600); err != nil {
			return metadata, err
		}
	}
	return metadata, writeBuildMetadata(output, metadata)
}
func writeBuildMetadata(output string, metadata BuildMetadata) error {
	data, err := json.MarshalIndent(metadata, "", "  ")
	if err != nil {
		return err
	}
	return atomicWrite(output+".ms-build.json", append(data, '\n'), 0644)
}

// VerifyBuild refuses stale source or binary metadata before source inspection/debugging.
func VerifyBuild(output string, sources map[string]string) error {
	data, err := os.ReadFile(output + ".ms-build.json")
	if err != nil {
		return err
	}
	var metadata BuildMetadata
	if err := json.Unmarshal(data, &metadata); err != nil {
		return err
	}
	binary, err := os.ReadFile(output)
	if err != nil {
		return err
	}
	if metadata.Format != 1 || digest(binary) != metadata.ExecutableSHA256 {
		return fmt.Errorf("executable does not match build metadata")
	}
	names := make([]string, 0, len(metadata.Sources))
	for name := range metadata.Sources {
		names = append(names, name)
	}
	sort.Strings(names)
	for _, name := range names {
		source, ok := sources[name]
		if !ok || digest([]byte(source)) != metadata.Sources[name] {
			return fmt.Errorf("source does not match build metadata: %s", name)
		}
	}
	return nil
}
