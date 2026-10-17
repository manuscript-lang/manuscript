package cli

import (
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"github.com/manuscript-lang/manuscript/pkg/compiler"
	"github.com/manuscript-lang/manuscript/pkg/project"
	"github.com/manuscript-lang/manuscript/pkg/tooling"
)

func runFormat(args []string) int {
	check, structured, positional, drop := false, false, false, false
	var targets []string
	for _, arg := range args {
		switch {
		case !positional && arg == "--":
			positional = true
		case !positional && arg == "--check":
			check = true
		case !positional && arg == "--json":
			structured = true
		case !positional && arg == "--drop-labels":
			drop = true
		case !positional && strings.HasPrefix(arg, "-"):
			fmt.Fprintf(os.Stderr, "unknown option %s for ms fmt; run 'ms help fmt' for its options\n", arg)
			return 2
		default:
			targets = append(targets, arg)
		}
	}
	if len(targets) == 0 {
		fmt.Fprintln(os.Stderr, "ms fmt: missing a target; pass .ms files, directories, or ms.toml")
		return 2
	}
	if structured && !check {
		fmt.Fprintln(os.Stderr, "--json requires ms fmt --check; remove --json to format files in place")
		return 2
	}
	cwd, err := formatCWD()
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 1
	}
	result := formatResult{Format: 1, Files: []formatFileResult{}, Diagnostics: []commandDiagnostic{}}
	status := 0
	report := func(target string, err error) {
		issue, message := formatError(cwd, target, err)
		result.Diagnostics = append(result.Diagnostics, issue)
		if !structured {
			fmt.Fprintln(os.Stderr, message)
		}
		status = 1
	}
	// Resolve and deduplicate before writing. Physical identity also determines
	// display spelling, regardless of how a file was selected.
	files := map[string]string{}
	sort.Strings(targets)
	for _, target := range targets {
		paths, err := formatPaths(target)
		if err != nil {
			report(target, err)
			continue
		}
		for _, path := range paths {
			absolute, err := filepath.Abs(path)
			if err == nil {
				absolute, err = filepath.EvalSymlinks(absolute)
			}
			if err != nil {
				report(path, err)
				continue
			}
			files[absolute] = formatDisplay(cwd, absolute)
		}
	}
	paths := make([]string, 0, len(files))
	for path := range files {
		paths = append(paths, path)
	}
	sort.Slice(paths, func(i, j int) bool { return files[paths[i]] < files[paths[j]] })
	for _, path := range paths {
		state, err := formatFile(path, files[path], check, drop)
		result.Files = append(result.Files, formatFileResult{files[path], state})
		if err != nil {
			report(path, err)
		}
	}
	if structured {
		sortDiagnostics(result.Diagnostics)
		return emitJSON(result, status)
	}
	return status
}

func formatPaths(target string) ([]string, error) {
	info, err := os.Stat(target)
	if err != nil {
		return nil, err
	}
	if !info.IsDir() && filepath.Base(target) != "ms.toml" {
		return []string{target}, nil
	}
	var config project.Project
	if info.IsDir() {
		root, err := filepath.Abs(target)
		if err != nil {
			return nil, err
		}
		root, err = filepath.EvalSymlinks(root)
		if err != nil {
			return nil, err
		}
		config = project.Project{Root: root, Source: root}
	} else {
		config, err = project.ReadProject(target)
		if err != nil {
			return nil, err
		}
	}
	paths, err := project.DiscoverModules(config, true)
	if err != nil {
		return nil, err
	}
	if config.Entry != "" {
		paths = append(paths, config.Entry)
	}
	// A discovered file symlink must stay inside the selected project/directory.
	// Explicit files remain independently selectable, including through symlinks.
	for i, path := range paths {
		paths[i], err = project.SourcePath(config.Root, path, nil)
		if err != nil {
			return nil, err
		}
	}
	return paths, nil
}

func formatFile(path, display string, check, dropLabels bool) (string, error) {
	source, err := os.ReadFile(path)
	if err != nil {
		return "error", err
	}
	text := string(source)
	if dropLabels {
		result := compiler.CompileFile(path, compiler.Options{AnalyzeOnly: true})
		if !result.Success() {
			first := result.Diagnostics[0]
			return "error", fmt.Errorf("%s:%d:%d: %s: %s\n--drop-labels needs source that checks (%d error(s)); fix them, then re-run ms fmt --drop-labels %s", display, first.Position.Line, first.Position.Column, first.Phase, first.Message, len(result.Diagnostics), display)
		}
		text, _ = tooling.DropRedundantLabels(result.Program, text)
	}
	formatted, err := tooling.Format(display, text)
	if err != nil {
		return "error", formatSourceError{display, err}
	}
	if string(source) == formatted {
		return "clean", nil
	}
	if check {
		return "needs_formatting", formatDrift{display}
	}
	info, err := os.Stat(path)
	if err != nil {
		return "error", err
	}
	if err := tooling.WriteFormatted(path, formatted, info.Mode().Perm()); err != nil {
		return "error", err
	}
	return "formatted", nil
}
