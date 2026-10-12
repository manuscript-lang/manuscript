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
	section := ""
	tables := map[string]bool{}
	seen := map[string]bool{}
	for scan.Scan() {
		line := strings.TrimSpace(manifestLine(scan.Text()))
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		if strings.HasPrefix(line, "[") {
			if line != "[project]" && line != "[aliases]" {
				return p, fmt.Errorf("unsupported manifest table %s", line)
			}
			if tables[line] {
				return p, fmt.Errorf("duplicate manifest table %s", line)
			}
			tables[line] = true
			section = strings.Trim(line, "[]")
			continue
		}
		key, value, ok := strings.Cut(line, "=")
		if !ok || section == "" {
			return p, fmt.Errorf("invalid manifest assignment")
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
			return p, fmt.Errorf("manifest values must be double-quoted strings")
		}
		value, err = strconv.Unquote(value)
		if err != nil {
			return p, fmt.Errorf("manifest values must be quoted strings: %w", err)
		}
		id := section + "." + key
		if seen[id] {
			return p, fmt.Errorf("duplicate manifest key %s", id)
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
				return p, fmt.Errorf("unknown project key %s", key)
			}
		} else {
			if !validAlias(key) || key == "@std" || strings.HasPrefix(value, "@") {
				return p, fmt.Errorf("invalid or reserved alias %s", key)
			}
			p.Aliases[key] = value
		}
	}
	if err := scan.Err(); err != nil {
		return p, err
	}
	if p.Name == "" || p.Source == "" || p.Entry == "" {
		return p, fmt.Errorf("project requires name, source, and entry")
	}
	p.Source, err = SourcePath(root, p.Source, nil)
	if err != nil {
		return p, err
	}
	info, err := os.Stat(p.Source)
	if err != nil || !info.IsDir() {
		return p, fmt.Errorf("project source must be an existing directory")
	}
	p.Entry, err = SourcePath(root, p.Entry, nil)
	if err != nil {
		return p, err
	}
	if filepath.Ext(p.Entry) != ".ms" {
		return p, fmt.Errorf("entry requires .ms extension")
	}
	info, err = os.Stat(p.Entry)
	if err != nil || !info.Mode().IsRegular() {
		return p, fmt.Errorf("project entry must be an existing regular file")
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
