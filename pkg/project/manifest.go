// Package project reads Manuscript manifests and resolves confined source paths.
// It has no dependency on parsing, checking, or native code generation.
package project

import (
	"bufio"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"unicode"
)

type Project struct {
	Root, Name, Source, Entry string
	Configuration             string
	Aliases                   map[string]string
	Location                  Location
	Assignments               map[string]Assignment
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
	p := Project{Root: root, Aliases: map[string]string{}, Location: Location{File: filepath.Base(absolute), Line: 1, Column: 1}, Assignments: map[string]Assignment{}}
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
	lineNumber, offset := 0, 0
	location := p.Location
	fail := func(format string, args ...any) error {
		return &ManifestError{Location: location, Cause: fmt.Errorf(format, args...)}
	}
	section := ""
	tables := map[string]bool{}
	seen := map[string]bool{}
	for scan.Scan() {
		lineNumber++
		raw := scan.Text()
		lineStart := offset
		if end := strings.IndexByte(p.Configuration[offset:], '\n'); end >= 0 {
			offset += end + 1
		} else {
			offset = len(p.Configuration)
		}
		if lineNumber == 1 {
			if strings.HasPrefix(raw, "\ufeff") {
				lineStart += len("\ufeff")
				raw = strings.TrimPrefix(raw, "\ufeff")
			}
		}
		content := manifestLine(raw)
		line := strings.TrimSpace(content)
		leading := len(content) - len(strings.TrimLeftFunc(content, unicode.IsSpace))
		location = Location{File: filepath.Base(absolute), Line: lineNumber, Column: leading + 1, Offset: lineStart + leading}
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		if strings.HasPrefix(line, "[") {
			if strings.HasSuffix(line, "]") && !strings.HasPrefix(line, "[[") {
				line = "[" + strings.TrimSpace(line[1:len(line)-1]) + "]"
			}
			if line != "[project]" && line != "[aliases]" {
				return p, fail("unsupported manifest table %s; ms.toml supports only [project] and [aliases]", line)
			}
			if tables[line] {
				return p, fail("duplicate manifest table %s; merge its keys into the first one", line)
			}
			tables[line] = true
			section = strings.Trim(line, "[]")
			if section == "project" {
				p.Location = location
			}
			continue
		}
		var key, value string
		var ok bool
		if strings.HasPrefix(line, "\"") {
			quoted, rest, closed := quotedPrefix(line)
			if !closed {
				return p, fail("unterminated quoted key; close the key's double quote, e.g. \"name\" = \"value\"")
			}
			key, err = strconv.Unquote(quoted)
			if err != nil {
				return p, fail("invalid quoted key %s: %v; escape backslashes and quotes inside the key", quoted, err)
			}
			value, ok = strings.CutPrefix(strings.TrimSpace(rest), "=")
		} else {
			key, value, ok = strings.Cut(line, "=")
			key = strings.TrimSpace(key)
		}
		if !ok || section == "" {
			return p, fail("invalid manifest assignment; write key = \"value\" inside [project] or [aliases], after the table header")
		}
		keyLocation := location
		value = strings.TrimSpace(value)
		valueStart := len(line) - len(value)
		location.Column += valueStart
		location.Offset += valueStart
		if len(value) < 2 || value[0] != '"' || value[len(value)-1] != '"' {
			return p, fail("manifest values must be double-quoted strings; write %s = \"%s\"", strings.TrimSpace(key), strings.Trim(value, "\"' "))
		}
		value, err = strconv.Unquote(value)
		if err != nil {
			return p, fail("manifest values must be quoted strings: %v; escape backslashes and quotes inside the value", err)
		}
		if strings.ContainsFunc(value, func(r rune) bool { return r < ' ' || r == 0x7f }) {
			return p, fail("manifest value for %s contains a NUL or control character; remove it", key)
		}
		id := section + "." + key
		if seen[id] {
			location = keyLocation
			return p, fail("duplicate manifest key %s; each key may be set once", id)
		}
		seen[id] = true
		p.Assignments[id] = Assignment{Key: keyLocation, Value: location}
		if section == "project" {
			switch key {
			case "name":
				p.Name = value
			case "source":
				p.Source = value
			case "entry":
				p.Entry = value
			default:
				location = keyLocation
				return p, fail("unknown project key %s; [project] accepts name, source, and entry", key)
			}
		} else {
			if !validAlias(key) || key == "@std" {
				location = keyLocation
				return p, fail("invalid or reserved alias %s; aliases look like @lib (start with @, letters/digits/underscore), cannot be @std, and must map to a path, not another alias", key)
			}
			if strings.HasPrefix(value, "@") {
				return p, fail("invalid alias target %s; map it to a project-local path, not another alias", value)
			}
			p.Aliases[key] = value
		}
	}
	if err := scan.Err(); err != nil {
		if errors.Is(err, bufio.ErrTooLong) {
			lineNumber++
			location = Location{File: filepath.Base(absolute), Line: lineNumber, Column: 1, Offset: offset}
			return p, fail("line too long; keep each ms.toml line under 64 KiB")
		}
		return p, err
	}
	location = p.Location
	if p.Name == "" || p.Source == "" {
		return p, fail("[project] requires name and source; missing: %s, e.g. name = \"app\", source = \"src\" (add entry = \"src/main.ms\" for an executable)", missingKeys(p))
	}
	location = p.Assignments["project.source"].Value
	p.Source, err = SourcePath(root, p.Source, nil)
	if err != nil {
		return p, &ManifestError{Location: location, Cause: err}
	}
	info, err := os.Stat(p.Source)
	if err != nil || !info.IsDir() {
		return p, fail("project source must be an existing directory; %q does not exist or is not a directory, so create it or fix source in [project]", p.Source)
	}
	if entry, explicit := p.Assignments["project.entry"]; explicit {
		location = entry.Value
		if p.Entry == "" {
			return p, fail("project entry cannot be empty; omit entry for a library or set it to a .ms file such as \"src/main.ms\"")
		}
		p.Entry, err = SourcePath(root, p.Entry, nil)
		if err != nil {
			return p, &ManifestError{Location: location, Cause: err}
		}
		if filepath.Ext(p.Entry) != ".ms" {
			return p, fail("entry requires .ms extension; set entry to a .ms file such as \"src/main.ms\"")
		}
		info, err = os.Stat(p.Entry)
		if err != nil || !info.Mode().IsRegular() {
			return p, fail("project entry must be an existing regular file; create %s or fix entry in [project]", p.Entry)
		}
	}
	keys := make([]string, 0, len(p.Aliases))
	for key := range p.Aliases {
		keys = append(keys, key)
	}
	sort.Strings(keys)
	for _, key := range keys {
		location = p.Assignments["aliases."+key].Value
		target, err := SourcePath(root, p.Aliases[key], nil)
		if err != nil {
			return p, fail("alias %s target cannot be resolved: %v; external Manuscript dependency projects are unsupported, so copy the sources inside this project root and point the alias at that copy", key, err)
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
	return strings.Join(keys, ", ")
}

// quotedPrefix splits a leading double-quoted string, honoring backslash escapes.
func quotedPrefix(line string) (quoted, rest string, closed bool) {
	for i := 1; i < len(line); i++ {
		switch line[i] {
		case '\\':
			i++
		case '"':
			return line[:i+1], line[i+1:], true
		}
	}
	return "", "", false
}
