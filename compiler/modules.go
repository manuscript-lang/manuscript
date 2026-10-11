package compiler

import (
	"bufio"
	"fmt"
	"github.com/manuscript-lang/manuscript/parser"
	"github.com/manuscript-lang/manuscript/syntax"
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
	p.Source, err = inside(root, p.Source)
	if err != nil {
		return p, err
	}
	info, err := os.Stat(p.Source)
	if err != nil || !info.IsDir() {
		return p, fmt.Errorf("project source must be an existing directory")
	}
	p.Entry, err = inside(root, p.Entry)
	if err != nil {
		return p, err
	}
	if filepath.Ext(p.Entry) != ".ms" {
		return p, fmt.Errorf("entry requires .ms extension")
	}
	for key, value := range p.Aliases {
		target, err := inside(root, value)
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
func inside(root, path string) (string, error) {
	if !filepath.IsAbs(path) {
		path = filepath.Join(root, path)
	}
	canonical, err := filepath.EvalSymlinks(path)
	if err != nil {
		return "", err
	}
	rel, err := filepath.Rel(root, canonical)
	if err != nil || rel == ".." || strings.HasPrefix(rel, ".."+string(filepath.Separator)) {
		return "", fmt.Errorf("path escapes project root: %s", path)
	}
	return canonical, nil
}
func CompileFile(filename string, options Options) Result {
	absolute, err := filepath.Abs(filename)
	if err != nil {
		return loadError(filename, err)
	}
	project := Project{Root: filepath.Dir(absolute), Entry: absolute, Aliases: map[string]string{}}
	if filepath.Base(absolute) == "ms.toml" {
		project, err = ReadProject(absolute)
		if err != nil {
			return loadError(filename, err)
		}
		options.Entry = !options.Tests
	} else {
		project.Root, err = filepath.EvalSymlinks(project.Root)
		if err != nil {
			return loadError(filename, err)
		}
	}
	var modules []*syntax.Module
	imports := map[*syntax.Import]string{}
	active := map[string]bool{}
	loaded := map[string]*syntax.Module{}
	var visit func(string) (string, error)
	visit = func(filename string) (string, error) {
		canonical, err := inside(project.Root, filename)
		if err != nil {
			return "", err
		}
		logical, _ := filepath.Rel(project.Root, canonical)
		logical = filepath.ToSlash(logical)
		if active[canonical] {
			return "", fmt.Errorf("cyclic module dependency at %s", logical)
		}
		if loaded[canonical] != nil {
			return logical, nil
		}
		active[canonical] = true
		defer delete(active, canonical)
		source, err := os.ReadFile(canonical)
		if err != nil {
			return "", err
		}
		module, err := parser.Parse(logical, string(source))
		if err != nil {
			return "", err
		}
		loaded[canonical] = module
		for _, item := range module.Imports {
			if strings.HasPrefix(item.Path, "@std/") {
				continue
			}
			target, err := resolveImport(project, canonical, item.Path)
			if err != nil {
				return "", syntax.Diagnostic{Position: item.Pos, Phase: "resolution", Message: err.Error()}
			}
			key, err := visit(target)
			if err != nil {
				return "", err
			}
			imports[item] = key
		}
		modules = append(modules, module)
		return logical, nil
	}
	entry, err := visit(project.Entry)
	if err != nil {
		return loadError(filename, err)
	}
	result := compileModules(modules, imports, entry, options)
	if filepath.Base(absolute) == "ms.toml" {
		result.ProjectRoot = project.Root
		result.Configuration = project.Configuration
	}
	return result
}
func resolveImport(project Project, importer, path string) (string, error) {
	if strings.Contains(path, "\\") {
		return "", fmt.Errorf("import paths use / separators")
	}
	var target string
	if strings.HasPrefix(path, "./") || strings.HasPrefix(path, "../") {
		if filepath.Ext(path) != ".ms" {
			return "", fmt.Errorf("import path requires .ms extension")
		}
		target = filepath.Join(filepath.Dir(importer), path)
	} else if strings.HasPrefix(path, "@") {
		alias, remainder, _ := strings.Cut(path, "/")
		base := project.Aliases[alias]
		if base == "" {
			return "", fmt.Errorf("unknown import alias %s", alias)
		}
		info, err := os.Stat(base)
		if err != nil {
			return "", err
		}
		if info.IsDir() {
			if remainder == "" || filepath.Ext(remainder) != ".ms" {
				return "", fmt.Errorf("directory alias requires a .ms path")
			}
			target = filepath.Join(base, remainder)
		} else {
			if remainder != "" || filepath.Ext(base) != ".ms" {
				return "", fmt.Errorf("file alias does not accept a suffix")
			}
			target = base
		}
	} else {
		return "", fmt.Errorf("imports require a relative path or alias")
	}
	return inside(project.Root, target)
}
func loadError(file string, err error) Result {
	if d, ok := err.(syntax.Diagnostic); ok {
		return Result{Diagnostics: []syntax.Diagnostic{d}}
	}
	return Result{Diagnostics: []syntax.Diagnostic{{Position: syntax.Position{File: file, Line: 1, Column: 1}, Phase: "resolution", Message: err.Error()}}}
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
