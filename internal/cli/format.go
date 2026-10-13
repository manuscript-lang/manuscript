package cli

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"github.com/manuscript-lang/manuscript/pkg/project"
	"github.com/manuscript-lang/manuscript/pkg/tooling"
)

func runFormat(args []string) int {
	check, positional := false, false
	var targets []string
	for _, arg := range args {
		switch {
		case !positional && arg == "--":
			positional = true
		case !positional && arg == "--check":
			check = true
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
	// Resolve every target before writing, and deduplicate overlapping selections
	// by physical path. Keep a stable display spelling for explicit file targets.
	files := map[string]string{}
	status := 0
	sort.Strings(targets)
	for _, target := range targets {
		paths, err := formatPaths(target)
		if err != nil {
			fmt.Fprintln(os.Stderr, fileError(err))
			status = 1
			continue
		}
		for _, path := range paths {
			absolute, err := filepath.Abs(path)
			if err == nil {
				absolute, err = filepath.EvalSymlinks(absolute)
			}
			if err != nil {
				fmt.Fprintln(os.Stderr, fileError(err))
				status = 1
				continue
			}
			if previous, ok := files[absolute]; !ok || path < previous {
				files[absolute] = path
			}
		}
	}
	paths := make([]string, 0, len(files))
	for path := range files {
		paths = append(paths, path)
	}
	sort.Slice(paths, func(i, j int) bool { return files[paths[i]] < files[paths[j]] })
	for _, path := range paths {
		if err := formatFile(path, files[path], check); err != nil {
			fmt.Fprintln(os.Stderr, err)
			status = 1
		}
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

func formatFile(path, display string, check bool) error {
	source, err := os.ReadFile(path)
	if err != nil {
		return errors.New(fileError(err))
	}
	formatted, err := tooling.Format(display, string(source))
	if err != nil {
		return fmt.Errorf("%v\nfmt only formats source that parses; fix the syntax error above, then re-run ms fmt %s", err, display)
	}
	if string(source) == formatted {
		return nil
	}
	if check {
		return fmt.Errorf("Formatting needed: %s; run ms fmt %s to rewrite it", display, display)
	}
	info, err := os.Stat(path)
	if err != nil {
		return err
	}
	return tooling.WriteFormatted(path, formatted, info.Mode().Perm())
}
