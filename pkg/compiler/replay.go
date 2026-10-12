package compiler

import (
	"encoding/json"
	"fmt"
	"go/parser"
	"go/token"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"slices"
	"strconv"
	"strings"
)

// A replay profile records how the go command compiled and linked one
// application package in the shared workspace. A later build whose source has
// the same imports runs those two tool invocations directly. That skips the go
// command's package loading and staleness hashing of every dependency, which
// otherwise dominates an edit-and-rebuild after Go's package cache is warm.
// Any mismatch or failure falls back to go build, which refreshes the profile.
type replayProfile struct {
	Format       int      `json:"format"`
	Package      string   `json:"package"`
	Directory    string   `json:"directory"`
	Imports      []string `json:"imports"`
	Compile      []string `json:"compile"`
	Link         []string `json:"link"`
	LinkEnv      []string `json:"link_env"`
	ImportConfig string   `json:"import_config"`
	LinkConfig   string   `json:"link_config"`
	Archives     []string `json:"archives"`
}

const replayFormat = 1

// replayWork is the go command's spelling of its temporary build directory.
const replayWork = "$WORK"

func replayKey(kind BuildType, tags []string) (string, error) {
	tool, _, err := goToolchain()
	if err != nil {
		return "", err
	}
	toolchain, err := queryToolchain()
	if err != nil {
		return "", err
	}
	identity, _ := json.Marshal(struct {
		Format    int
		Tool      string
		Kind      BuildType
		Tags      []string
		Flags     []string
		Toolchain map[string]string
	}{replayFormat, tool, kind, tags, kind.nativeFlags(), toolchain})
	return digest(identity), nil
}

func replayPath(root, key string) string {
	return filepath.Join(root, "profiles", key[:32]+".json")
}

func sourceImports(source string) ([]string, error) {
	file, err := parser.ParseFile(token.NewFileSet(), "main.go", source, parser.ImportsOnly)
	if err != nil {
		return nil, err
	}
	var imports []string
	for _, spec := range file.Imports {
		path, err := strconv.Unquote(spec.Path.Value)
		if err != nil {
			return nil, err
		}
		imports = append(imports, path)
	}
	slices.Sort(imports)
	return slices.Compact(imports), nil
}

func loadReplay(root, key string, imports []string) (*replayProfile, bool) {
	data, err := os.ReadFile(replayPath(root, key))
	if err != nil {
		return nil, false
	}
	var profile replayProfile
	if json.Unmarshal(data, &profile) != nil || profile.Format != replayFormat || !slices.Equal(profile.Imports, imports) || len(profile.Compile) == 0 || len(profile.Link) == 0 {
		return nil, false
	}
	// Go may trim its package cache; a missing archive means the go command
	// must rebuild it.
	for _, archive := range profile.Archives {
		if _, err := os.Stat(archive); err != nil {
			return nil, false
		}
	}
	return &profile, true
}

// replay compiles and links dir/main.go into output with the recorded commands.
func (profile *replayProfile) replay(dir, packagePath, output string) error {
	_, environment, err := goToolchain()
	if err != nil {
		return err
	}
	work, err := os.MkdirTemp("", "manuscript-link-")
	if err != nil {
		return err
	}
	defer os.RemoveAll(work)
	unit := filepath.Join(work, "b001")
	if err := os.MkdirAll(filepath.Join(unit, "exe"), 0700); err != nil {
		return err
	}
	replacer := strings.NewReplacer(replayWork, work, profile.Directory, dir, profile.Package, packagePath)
	if err := os.WriteFile(filepath.Join(unit, "importcfg"), []byte(replacer.Replace(profile.ImportConfig)), 0600); err != nil {
		return err
	}
	if err := os.WriteFile(filepath.Join(unit, "importcfg.link"), []byte(replacer.Replace(profile.LinkConfig)), 0600); err != nil {
		return err
	}
	rewrite := func(arguments []string) []string {
		rewritten := make([]string, len(arguments))
		for i, argument := range arguments {
			rewritten[i] = replacer.Replace(argument)
		}
		return rewritten
	}
	run := func(arguments, extra []string) error {
		command := exec.Command(arguments[0], arguments[1:]...)
		command.Dir = dir
		command.Env = append(append([]string{}, environment...), extra...)
		if data, err := command.CombinedOutput(); err != nil {
			return fmt.Errorf("%s: %w\n%s", filepath.Base(arguments[0]), err, data)
		}
		return nil
	}
	if err := run(rewrite(profile.Compile), nil); err != nil {
		return err
	}
	if err := run(rewrite(profile.Link), profile.LinkEnv); err != nil {
		return err
	}
	return moveFile(filepath.Join(unit, "exe", "a.out"), output)
}

// captureReplay derives a profile from go build -x -work output. It returns
// false when the output lacks a compile and link of package main, as when Go
// reused a cached compilation of identical source.
func captureReplay(trace []byte, dir, packagePath string, imports []string) (*replayProfile, bool) {
	var work string
	profile := &replayProfile{Format: replayFormat, Package: packagePath, Directory: dir, Imports: imports}
	for _, line := range strings.Split(string(trace), "\n") {
		line = strings.TrimRight(line, "\r")
		if value, ok := strings.CutPrefix(line, "WORK="); ok {
			work = value
			continue
		}
		environment, arguments, ok := splitTraceCommand(line)
		if !ok || len(arguments) == 0 {
			continue
		}
		switch tool := strings.TrimSuffix(filepath.Base(arguments[0]), ".exe"); {
		case tool == "compile" && hasArguments(arguments, "-p", "main"):
			profile.Compile = withoutBuildID(arguments)
			if len(environment) != 0 {
				return nil, false
			}
		case tool == "link" && slices.Contains(arguments, "-buildmode=exe"):
			profile.Link = withoutBuildID(arguments)
			profile.LinkEnv = environment
		}
	}
	if work == "" || profile.Compile == nil || profile.Link == nil || !filepath.IsAbs(profile.Compile[0]) || !filepath.IsAbs(profile.Link[0]) {
		return nil, false
	}
	unit := filepath.Join(work, "b001")
	importConfig, err := os.ReadFile(filepath.Join(unit, "importcfg"))
	if err != nil {
		return nil, false
	}
	linkConfig, err := os.ReadFile(filepath.Join(unit, "importcfg.link"))
	if err != nil {
		return nil, false
	}
	// Only the application's own archive is recreated in the replay work
	// directory; dependencies the go command just compiled there are not.
	profile.ImportConfig = strings.ReplaceAll(string(importConfig), work, replayWork)
	profile.LinkConfig = strings.ReplaceAll(string(linkConfig), work, replayWork)
	for _, config := range []string{profile.ImportConfig, profile.LinkConfig} {
		for _, line := range strings.Split(config, "\n") {
			if entry, ok := strings.CutPrefix(line, "packagefile "); ok {
				_, archive, found := strings.Cut(entry, "=")
				if !found {
					return nil, false
				}
				if archive == filepath.Join(replayWork, "b001", "_pkg_.a") {
					continue
				}
				if !filepath.IsAbs(archive) {
					return nil, false
				}
				profile.Archives = append(profile.Archives, archive)
			}
		}
	}
	slices.Sort(profile.Archives)
	profile.Archives = slices.Compact(profile.Archives)
	// Every remaining work path must be one replay recreates.
	for _, argument := range append(append([]string{}, profile.Compile...), profile.Link...) {
		if strings.Contains(argument, work) {
			return nil, false
		}
	}
	return profile, true
}

func saveReplay(root, key string, profile *replayProfile) error {
	data, err := json.Marshal(profile)
	if err != nil {
		return err
	}
	path := replayPath(root, key)
	if err := os.MkdirAll(filepath.Dir(path), 0755); err != nil {
		return err
	}
	return replaceFile(path, data, 0644)
}

func hasArguments(arguments []string, flag, value string) bool {
	for i := 0; i+1 < len(arguments); i++ {
		if arguments[i] == flag && arguments[i+1] == value {
			return true
		}
	}
	return false
}

// Replayed outputs omit the go command's build IDs, which only serve its own
// staleness checks; artifact identity is recorded in build metadata instead.
func withoutBuildID(arguments []string) []string {
	var kept []string
	for i := 0; i < len(arguments); i++ {
		switch {
		case arguments[i] == "-buildid" && i+1 < len(arguments):
			i++
		case strings.HasPrefix(arguments[i], "-buildid="):
		default:
			kept = append(kept, arguments[i])
		}
	}
	return kept
}

// splitTraceCommand parses one go -x command line: optional NAME='value'
// assignments, then arguments that are bare or quoted with strconv.Quote.
func splitTraceCommand(line string) ([]string, []string, bool) {
	var environment, arguments []string
	for line = strings.TrimSpace(line); line != ""; line = strings.TrimLeft(line, " ") {
		if strings.HasPrefix(line, "#") {
			break
		}
		var word string
		if line[0] == '"' {
			end := 1
			for ; end < len(line) && line[end] != '"'; end++ {
				if line[end] == '\\' {
					end++
				}
			}
			if end >= len(line) {
				return nil, nil, false
			}
			unquoted, err := strconv.Unquote(line[:end+1])
			if err != nil {
				return nil, nil, false
			}
			word, line = unquoted, line[end+1:]
		} else {
			end := strings.IndexByte(line, ' ')
			if end < 0 {
				end = len(line)
			}
			word, line = line[:end], line[end:]
		}
		if len(arguments) == 0 {
			if name, value, ok := strings.Cut(word, "="); ok && isEnvironmentName(name) {
				if len(value) >= 2 && value[0] == '\'' && value[len(value)-1] == '\'' {
					value = value[1 : len(value)-1]
				}
				if strings.ContainsAny(value, "'\"") {
					return nil, nil, false
				}
				environment = append(environment, name+"="+value)
				continue
			}
		}
		arguments = append(arguments, word)
	}
	return environment, arguments, true
}

func isEnvironmentName(name string) bool {
	if name == "" {
		return false
	}
	for i, r := range name {
		if !(r == '_' || r >= 'A' && r <= 'Z' || i > 0 && r >= '0' && r <= '9') {
			return false
		}
	}
	return true
}

func moveFile(source, target string) error {
	if err := os.Rename(source, target); err == nil {
		return nil
	}
	input, err := os.Open(source)
	if err != nil {
		return err
	}
	defer input.Close()
	file, err := os.CreateTemp(filepath.Dir(target), ".manuscript-write-*")
	if err != nil {
		return err
	}
	defer os.Remove(file.Name())
	if _, err := io.Copy(file, input); err != nil {
		file.Close()
		return err
	}
	if err := file.Chmod(0755); err != nil {
		file.Close()
		return err
	}
	if err := file.Close(); err != nil {
		return err
	}
	return os.Rename(file.Name(), target)
}

func traceWork(trace []byte) string {
	for _, line := range strings.Split(string(trace), "\n") {
		if work, ok := strings.CutPrefix(strings.TrimRight(line, "\r"), "WORK="); ok && filepath.IsAbs(work) {
			return work
		}
	}
	return ""
}
