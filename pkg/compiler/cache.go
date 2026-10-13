package compiler

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	support "github.com/manuscript-lang/manuscript"
	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/frontend"
	"github.com/manuscript-lang/manuscript/pkg/lexer"
	"github.com/manuscript-lang/manuscript/pkg/parser"
	"github.com/manuscript-lang/manuscript/pkg/project"
	msruntime "github.com/manuscript-lang/manuscript/pkg/runtime"
	"github.com/manuscript-lang/manuscript/pkg/stdlib"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
	"io"
	"io/fs"
	"os"
	"path/filepath"
	"reflect"
	goruntime "runtime"
	"sort"
	"strings"
	"sync"
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
	BuildType           BuildType         `json:"build_type"`
	Debug               bool              `json:"debug"`
}

func digest(data []byte) string { sum := sha256.Sum256(data); return hex.EncodeToString(sum[:]) }

// Embedded inputs are fixed for the life of a process, so hash them once.
// Files hash concurrently; the combined digest keeps the sorted walk order.
var implementation = sync.OnceValue(func() string {
	bundles := []struct {
		name  string
		files fs.FS
	}{{"lexer", lexer.ImplementationSources}, {"parser", parser.ImplementationSources}, {"frontend", frontend.ImplementationSources}, {"checker", checker.ImplementationSources}, {"syntax", syntax.ImplementationSources}, {"project", project.ImplementationSources}, {"compiler", ImplementationSources}, {"runtime", msruntime.Sources}, {"dependencies", support.NativeDependencies}, {"stdlib", stdlib.Sources}}
	return bundleDigest(bundles)
})

func implementationDigest() string { return implementation() }

func bundleDigest(bundles []struct {
	name  string
	files fs.FS
}) string {
	var data strings.Builder
	for _, bundle := range bundles {
		data.WriteString(bundleListing(bundle.name, bundle.files))
	}
	return digest([]byte(data.String()))
}

// Bundle listings are shared by implementation and workspace identities.
var bundleListings sync.Map

// bundleListing names each non-test file with its content digest in walk order.
func bundleListing(name string, files fs.FS) string {
	if listing, ok := bundleListings.Load(name); ok {
		return listing.(string)
	}
	type entry struct{ path, sum string }
	var entries []*entry
	fs.WalkDir(files, ".", func(path string, item fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if !item.IsDir() && !strings.HasSuffix(path, "_test.go") {
			entries = append(entries, &entry{path: path})
		}
		return nil
	})
	var group sync.WaitGroup
	next := make(chan *entry, len(entries))
	for _, item := range entries {
		next <- item
	}
	close(next)
	for range goruntime.GOMAXPROCS(0) {
		group.Add(1)
		go func() {
			defer group.Done()
			for item := range next {
				if contents, err := fs.ReadFile(files, item.path); err == nil {
					item.sum = digest(contents)
				}
			}
		}()
	}
	group.Wait()
	var listing strings.Builder
	for _, item := range entries {
		if item.sum != "" {
			listing.WriteString(name + "/" + item.path + "\x00" + item.sum + "\n")
		}
	}
	actual, _ := bundleListings.LoadOrStore(name, listing.String())
	return actual.(string)
}
func CurrentPin() (BuildPin, error) {
	toolchain, err := queryToolchain()
	if err != nil {
		return BuildPin{}, err
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

var errMissingPin = errors.New("ms.lock not found")

func readPin(root string) (BuildPin, error) {
	data, err := os.ReadFile(filepath.Join(root, "ms.lock"))
	if errors.Is(err, os.ErrNotExist) {
		return BuildPin{}, errMissingPin
	}
	if err != nil {
		return BuildPin{}, fmt.Errorf("project build requires ms.lock; run ms lock %s: %w", shellQuote(filepath.Join(root, "ms.toml")), err)
	}
	var pin BuildPin
	decoder := json.NewDecoder(strings.NewReader(string(data)))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&pin); err != nil {
		return BuildPin{}, fmt.Errorf("invalid ms.lock: %w; it is generated, so delete it and run ms lock ms.toml to recreate it", err)
	}
	if err := decoder.Decode(new(any)); err != io.EOF {
		return BuildPin{}, fmt.Errorf("ms.lock must contain exactly one JSON object; it is generated, so delete it and run ms lock ms.toml to recreate it")
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
		return fmt.Errorf("ms.lock does not match compiler/runtime, Go toolchain, or target; run ms lock %s to explicitly update", shellQuote(filepath.Join(root, "ms.toml")))
	}
	return nil
}

func atomicWrite(filename string, data []byte, mode os.FileMode) error {
	return writeReplacing(filename, data, mode, true)
}

// replaceFile atomically replaces derived files whose contents are verified
// or regenerated on use, so it does not wait for them to reach stable storage.
func replaceFile(filename string, data []byte, mode os.FileMode) error {
	return writeReplacing(filename, data, mode, false)
}

func writeReplacing(filename string, data []byte, mode os.FileMode, durable bool) error {
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
	if durable {
		if err := file.Sync(); err != nil {
			file.Close()
			return err
		}
	}
	if err := file.Close(); err != nil {
		return err
	}
	return os.Rename(name, filename)
}

// BuildChecked caches only verified native artifacts. Parsing/checking still precedes it.
func BuildChecked(result Result, output, cacheDir string, debug bool) (BuildMetadata, error) {
	kind := Release
	if debug {
		kind = Debug
	}
	return BuildCheckedWithType(result, output, cacheDir, kind)
}

// BuildCheckedWithType caches verified artifacts separately for each build type.
func BuildCheckedWithType(result Result, output, cacheDir string, kind BuildType) (BuildMetadata, error) {
	kind, err := ParseBuildType(string(kind))
	if err != nil {
		return BuildMetadata{}, err
	}
	if !result.Success() || result.Program == nil || result.Source == "" {
		return BuildMetadata{}, fmt.Errorf("cannot build a program with diagnostics; run ms check on the source and fix the reported errors first")
	}
	var expected BuildPin
	if result.ProjectRoot != "" {
		var err error
		expected, err = readPin(result.ProjectRoot)
		if errors.Is(err, errMissingPin) {
			// A project without ms.lock is pinned on first build; an existing
			// pin that no longer matches still needs an explicit ms lock.
			if err = WritePin(result.ProjectRoot); err == nil {
				expected, err = readPin(result.ProjectRoot)
			}
		}
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
	metadata := BuildMetadata{BuildPin: pin, Sources: map[string]string{}, ConfigurationSHA256: digest([]byte(result.Configuration)), BuildType: kind, Debug: kind == Debug}
	if result.ProjectRoot != "" {
		metadata.Sources["ms.toml"] = digest([]byte(result.Configuration))
	}
	for _, module := range result.Program.Modules {
		metadata.Sources[module.File] = digest([]byte(module.Source))
	}
	source := result.Source
	if kind.sourcePaths() {
		source = debugSource(result)
		metadata.SourceRoot = result.SourceRoot
	}
	tags := runtimeTags(result.Program)
	identity, _ := json.Marshal(struct {
		Metadata        BuildMetadata
		GeneratedSHA256 string
		RuntimeTags     []string `json:",omitempty"`
	}{metadata, digest([]byte(source)), tags})
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
			binaryDigest, binaryErr := fileDigest(cacheBinary)
			if json.Unmarshal(info, &cached) == nil && cached.BuildID == metadata.BuildID && binaryErr == nil && binaryDigest == cached.ExecutableSHA256 {
				expected := metadata
				expected.ExecutableSHA256 = cached.ExecutableSHA256
				if reflect.DeepEqual(expected, cached) {
					if err := publishArtifact(cacheBinary, output, binaryDigest); err != nil {
						return metadata, err
					}
					return cached, writeBuildMetadata(output, cached)
				}
			}
		}
	}
	built := output
	if cacheDir != "" {
		// Build beside the cache entry, then publish one file to both places.
		staging, err := os.MkdirTemp(cacheDir, ".build-")
		if err != nil {
			return metadata, err
		}
		defer os.RemoveAll(staging)
		built = filepath.Join(staging, "program")
	}
	if err := buildNative(source, built, kind, tags); err != nil {
		return metadata, err
	}
	executable, err := fileDigest(built)
	if err != nil {
		return metadata, err
	}
	metadata.ExecutableSHA256 = executable
	if cacheDir != "" {
		if err := os.Rename(built, cacheBinary); err != nil {
			return metadata, err
		}
		data, _ := json.Marshal(metadata)
		if err := replaceFile(cacheMetadata, data, 0600); err != nil {
			return metadata, err
		}
		if err := publishArtifact(cacheBinary, output, executable); err != nil {
			return metadata, err
		}
	}
	return metadata, writeBuildMetadata(output, metadata)
}

func fileDigest(filename string) (string, error) {
	file, err := os.Open(filename)
	if err != nil {
		return "", err
	}
	defer file.Close()
	hash := sha256.New()
	if _, err := io.Copy(hash, file); err != nil {
		return "", err
	}
	return hex.EncodeToString(hash.Sum(nil)), nil
}

// publishArtifact places a verified cached executable at target. It shares
// the file when the file system allows, and leaves a matching target as is.
// Cache hits re-verify content hashes, so a later change to either name
// cannot run as the cached artifact.
func publishArtifact(cached, target, contents string) error {
	source, err := os.Stat(cached)
	if err != nil {
		return err
	}
	if existing, err := os.Stat(target); err == nil && existing.Size() == source.Size() {
		if os.SameFile(source, existing) {
			return os.Chmod(target, 0755)
		}
		if digest, err := fileDigest(target); err == nil && digest == contents {
			return os.Chmod(target, 0755)
		}
	}
	staging := filepath.Join(filepath.Dir(target), fmt.Sprintf(".manuscript-link-%d-%s", os.Getpid(), contents[:16]))
	os.Remove(staging)
	if err := os.Link(cached, staging); err == nil {
		if err := os.Rename(staging, target); err != nil {
			os.Remove(staging)
			return err
		}
		return nil
	}
	data, err := os.ReadFile(cached)
	if err != nil {
		return err
	}
	return replaceFile(target, data, 0755)
}

func writeBuildMetadata(output string, metadata BuildMetadata) error {
	data, err := json.MarshalIndent(metadata, "", "  ")
	if err != nil {
		return err
	}
	return replaceFile(output+".ms-build.json", append(data, '\n'), 0644)
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
		return fmt.Errorf("executable does not match build metadata; the cached build is stale or was modified, so delete it (or the MANUSCRIPT_CACHE_DIR entry) and rebuild")
	}
	names := make([]string, 0, len(metadata.Sources))
	for name := range metadata.Sources {
		names = append(names, name)
	}
	sort.Strings(names)
	for _, name := range names {
		source, ok := sources[name]
		if !ok || digest([]byte(source)) != metadata.Sources[name] {
			return fmt.Errorf("source does not match build metadata: %s changed since the build; rebuild to refresh the artifact", name)
		}
	}
	return nil
}

// shellQuote makes a path safe to paste into a command hint.
func shellQuote(path string) string {
	if path != "" && !strings.ContainsAny(path, " \t\n'\"\\$`&;|<>()*?[]{}!#~") {
		return path
	}
	return `"` + strings.NewReplacer(`\`, `\\`, `"`, `\"`, "$", `\$`, "`", "\\`").Replace(path) + `"`
}
