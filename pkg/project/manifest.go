// Package project reads Manuscript manifests and resolves confined source paths.
// It has no dependency on parsing, checking, or native code generation.
package project

import (
	"bufio"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strconv"
	"strings"
)

type Project struct {
	Root, Name, Source, Entry string
	Configuration             string
	Aliases                   map[string]string
}

// FindManifest returns the nearest containing manifest, even if it is invalid.
// A nested project's errors must not silently select a parent's configuration.
func FindManifest(filename string) (string, bool) {
	for dir := filepath.Dir(filename); ; dir = filepath.Dir(dir) {
		manifest := filepath.Join(dir, "ms.toml")
		if _, err := os.Stat(manifest); err == nil {
			return manifest, true
		}
		if filepath.Dir(dir) == dir {
			return "", false
		}
	}
}

// ReadProject validates the supported ms.toml subset and canonicalizes its paths.
func ReadProject(filename string) (Project, error) {
	absolute, err := filepath.Abs(filename)
	if err != nil {
		return Project{}, err
	}
	root, err := filepath.EvalSymlinks(filepath.Dir(absolute))
	if err != nil {
		return Project{}, err
	}
	p := Project{Root: root, Aliases: map[string]string{}}
	file, err := os.Open(absolute)
	if err != nil {
		return p, err
	}
	defer file.Close()
	data, err := io.ReadAll(file)
	if err != nil {
		return p, err
	}
	p.Configuration = string(data)
	scan := bufio.NewScanner(strings.NewReader(p.Configuration))
	lineNumber := 0
	fail := func(format string, args ...any) error {
		return fmt.Errorf("%s:%d: %s", filepath.Base(absolute), lineNumber, fmt.Sprintf(format, args...))
	}
	section := ""
	tables := map[string]bool{}
	seen := map[string]bool{}
	for scan.Scan() {
		lineNumber++
		line := strings.TrimSpace(manifestLine(scan.Text()))
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		if strings.HasPrefix(line, "[") {
			if line != "[project]" && line != "[aliases]" {
				return p, fail("unsupported manifest table %s; ms.toml supports only [project] and [aliases]", line)
			}
			if tables[line] {
				return p, fail("duplicate manifest table %s; merge its keys into the first one", line)
			}
			tables[line] = true
			section = strings.Trim(line, "[]")
			continue
		}
		key, value, ok := strings.Cut(line, "=")
		if !ok || section == "" {
			return p, fail("invalid manifest assignment; write key = \"value\" inside [project] or [aliases], after the table header")
		}
		key = strings.TrimSpace(key)
		if strings.HasPrefix(key, "\"") {
			key, err = strconv.Unquote(key)
			if err != nil {
				return p, err
			}
		}
		value = strings.TrimSpace(value)
		if len(value) < 2 || value[0] != '"' || value[len(value)-1] != '"' {
			return p, fail("manifest values must be double-quoted strings; write %s = \"%s\"", strings.TrimSpace(key), strings.Trim(value, "\"' "))
		}
		value, err = strconv.Unquote(value)
		if err != nil {
			return p, fail("manifest values must be quoted strings: %v; escape backslashes and quotes inside the value", err)
		}
		id := section + "." + key
		if seen[id] {
			return p, fail("duplicate manifest key %s; each key may be set once", id)
		}
		seen[id] = true
		if section == "project" {
			switch key {
			case "name":
				p.Name = value
			case "source":
				p.Source = value
			case "entry":
				p.Entry = value
			default:
				return p, fail("unknown project key %s; [project] accepts name, source, and entry", key)
			}
		} else {
			if !validAlias(key) || key == "@std" || strings.HasPrefix(value, "@") {
				return p, fail("invalid or reserved alias %s; aliases look like @lib (start with @, letters/digits/underscore), cannot be @std, and must map to a path, not another alias", key)
			}
			p.Aliases[key] = value
		}
	}
	if err := scan.Err(); err != nil {
		return p, err
	}
	if p.Name == "" || p.Source == "" || p.Entry == "" {
		return p, fmt.Errorf("%s: [project] requires name, source, and entry; missing: %s, e.g. name = \"app\", source = \"src\", entry = \"src/main.ms\"", filepath.Base(absolute), missingKeys(p))
	}
	p.Source, err = SourcePath(root, p.Source, nil)
	if err != nil {
		return p, err
	}
	info, err := os.Stat(p.Source)
	if err != nil || !info.IsDir() {
		return p, fmt.Errorf("%s: project source must be an existing directory; %q does not exist or is not a directory, so create it or fix source in [project]", filepath.Base(absolute), p.Source)
	}
	p.Entry, err = SourcePath(root, p.Entry, nil)
	if err != nil {
		return p, err
	}
	if filepath.Ext(p.Entry) != ".ms" {
		return p, fmt.Errorf("%s: entry requires .ms extension; set entry to a .ms file such as \"src/main.ms\"", filepath.Base(absolute))
	}
	info, err = os.Stat(p.Entry)
	if err != nil || !info.Mode().IsRegular() {
		return p, fmt.Errorf("%s: project entry must be an existing regular file; create %s or fix entry in [project]", filepath.Base(absolute), p.Entry)
	}
	for key, value := range p.Aliases {
		target, err := SourcePath(root, value, nil)
		if err != nil {
			return p, err
		}
		p.Aliases[key] = target
	}
	return p, nil
}
func validAlias(key string) bool {
	if len(key) < 2 || key[0] != '@' {
		return false
	}
	for i, r := range key[1:] {
		if !(r >= 'a' && r <= 'z' || r >= 'A' && r <= 'Z' || r == '_' || i > 0 && r >= '0' && r <= '9') {
			return false
		}
	}
	return true
}
func manifestLine(line string) string {
	quoted, escaped := false, false
	for i, c := range line {
		if escaped {
			escaped = false
			continue
		}
		if quoted && c == '\\' {
			escaped = true
			continue
		}
		if c == '"' {
			quoted = !quoted
		}
		if c == '#' && !quoted {
			return line[:i]
		}
	}
	return line
}

func missingKeys(p Project) string {
	var keys []string
	if p.Name == "" {
		keys = append(keys, "name")
	}
	if p.Source == "" {
		keys = append(keys, "source")
	}
	if p.Entry == "" {
		keys = append(keys, "entry")
	}
	return strings.Join(keys, ", ")
}
