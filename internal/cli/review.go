package cli

import (
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"

	"github.com/manuscript-lang/manuscript/pkg/compiler"
	"github.com/manuscript-lang/manuscript/pkg/tooling"
)

type reviewArguments struct {
	filename, diff, format, output, explain string
	all, json                               bool
}

// parseReviewArguments reads ms review's options; a false result carries the
// status for the problem already reported.
func parseReviewArguments(args []string) (reviewArguments, int, bool) {
	var a reviewArguments
	if len(args) < 2 {
		return a, usageError("ms review: missing the file argument; pass a .ms file or a project ms.toml, e.g. ms review ms.toml"), false
	}
	if strings.HasPrefix(args[1], "-") {
		return a, usageError("unknown option %s for ms review; run 'ms help review' for its options (put the file first, then options)", args[1]), false
	}
	filename, err := resolveInput("review", args[1])
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		return a, 2, false
	}
	a.filename = filename
	for i := 2; i < len(args); i++ {
		flag, value, inline := splitValueOption(args[i], "--diff", "--format", "--explain", "-o", "--output")
		switch flag {
		case "--all":
			a.all = true
		case "--json":
			a.json = true
		case "--diff", "--format", "--explain", "-o", "--output":
			value, ok := requiredValue(args, &i, value, inline)
			if !ok {
				return a, usageError("%s requires a value; run 'ms help review' for examples", flag), false
			}
			switch flag {
			case "--diff":
				a.diff = value
			case "--format":
				a.format = value
			case "--explain":
				a.explain = value
			default:
				a.output = value
			}
		default:
			return a, usageError("unknown option %s for ms review; run 'ms help review' for its options", args[i]), false
		}
	}
	switch {
	case a.json && a.format != "":
		return a, usageError("--json and --format cannot be combined; --json is the JSON report"), false
	case a.json && a.explain != "":
		return a, usageError("--explain prints text and cannot be combined with --json"), false
	case a.json:
		a.format = "json"
	case a.format == "":
		a.format = "ascii"
	case a.format != "ascii" && a.format != "markdown":
		return a, usageError("unknown --format %q for ms review; use ascii or markdown (--json for JSON)", a.format), false
	}
	if a.explain != "" && a.diff == "" {
		return a, usageError("--explain needs --diff; it explains one finding of a diff report, e.g. ms review ms.toml --diff change.patch --explain 1"), false
	}
	return a, 0, true
}

// runReview reports where a reader should look: the project as it is, or the
// semantic difference a unified diff makes. ms never runs git; the diff is input.
func runReview(args []string, _ string) int {
	a, status, ok := parseReviewArguments(args)
	if !ok {
		return status
	}
	options := compiler.Options{AnalyzeOnly: true, Entry: filepath.Base(a.filename) == "ms.toml"}
	head := compiler.CompileFile(a.filename, options)
	if !head.Success() {
		return reportDiagnostics(head)
	}
	headFacts := tooling.CollectFacts(head.Program)
	reviewOptions := tooling.ReviewOptions{All: a.all}
	if a.diff == "" {
		return writeOutput(a.output, []byte(tooling.ProjectReport(headFacts, reviewOptions).Render(a.format)))
	}
	input, baseFacts, status := diffInputs(a.filename, a.diff, head, options.Entry)
	if status != 0 {
		return status
	}
	if a.explain != "" {
		text, err := tooling.Explain(tooling.CompareFacts(baseFacts, headFacts, input), headFacts, a.explain)
		if err != nil {
			fmt.Fprintf(os.Stderr, "ms review: %v\n", err)
			return 2
		}
		return writeOutput(a.output, []byte(text))
	}
	return writeOutput(a.output, []byte(tooling.DiffReport(baseFacts, headFacts, input, reviewOptions).Render(a.format)))
}

// diffInputs reads the unified diff, rebuilds the base program from it, and
// returns the change summary with the base facts; a nonzero status means the
// problem is already reported.
func diffInputs(filename, diff string, head compiler.Result, entry bool) (tooling.DiffInput, tooling.Facts, int) {
	var none tooling.Facts
	text, err := readDiff(diff)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		return tooling.DiffInput{}, none, 2
	}
	files, err := tooling.ParseDiff(text)
	if err != nil {
		fmt.Fprintf(os.Stderr, "ms review: %v; pass a unified diff such as git diff --no-renames main...\n", err)
		return tooling.DiffInput{}, none, 2
	}
	root := head.ProjectRoot
	if root == "" {
		absolute, _ := filepath.Abs(filename)
		root = filepath.Dir(absolute)
	}
	input, overlay, err := reviewInput(files, root)
	if err != nil {
		fmt.Fprintf(os.Stderr, "ms review: diff does not match the tree: %v; run it from the checkout the diff was made against\n", err)
		return input, none, 2
	}
	base := compiler.CompileFile(filename, compiler.Options{AnalyzeOnly: true, Entry: entry, Overlay: overlay})
	var baseFacts tooling.Facts
	if base.Success() {
		input.BaseChecked = true
		baseFacts = tooling.CollectFacts(base.Program)
	}
	return input, baseFacts, 0
}

func readDiff(path string) (string, error) {
	var data []byte
	var err error
	if path == "-" {
		data, err = io.ReadAll(os.Stdin)
	} else {
		data, err = os.ReadFile(path)
	}
	if err != nil {
		return "", fmt.Errorf("ms review: cannot read the diff: %s", fileError(err))
	}
	return string(data), nil
}

// reviewInput maps the diff onto the project and rebuilds each changed file's
// base text into an overlay. Only .ms files inside the project take part.
func reviewInput(files []tooling.DiffFile, root string) (tooling.DiffInput, map[string]string, error) {
	input := tooling.DiffInput{Files: len(files), Added: map[string]bool{}, Touched: map[string][]int{}}
	overlay := map[string]string{}
	for _, file := range files {
		for _, hunk := range file.Hunks {
			for _, line := range hunk.Lines {
				switch line[0] {
				case '+':
					input.Insertions++
				case '-':
					input.Deletions++
				}
			}
		}
		if filepath.Ext(file.Path()) != ".ms" {
			continue
		}
		absolute := locateDiffPath(root, file.Path(), file.New == "")
		relative, err := filepath.Rel(root, absolute)
		if err != nil || strings.HasPrefix(relative, "..") {
			continue
		}
		input.Sources++
		relative = filepath.ToSlash(relative)
		switch {
		case file.Old == "":
			input.Added[relative] = true
		case file.New == "":
			overlay[absolute] = tooling.RemovedContent(file.Hunks)
		default:
			head, err := os.ReadFile(absolute)
			if err != nil {
				return input, nil, fmt.Errorf("%s: %s", file.Path(), fileError(err))
			}
			base, err := tooling.ReverseApply(string(head), file.Hunks)
			if err != nil {
				return input, nil, fmt.Errorf("%s: %v", file.Path(), err)
			}
			overlay[absolute] = base
		}
		if file.New != "" {
			input.Touched[relative] = file.TouchedLines()
		}
	}
	return input, overlay, nil
}

// locateDiffPath finds the diff's repository-relative path at or above the
// project root, since the project may live in a subdirectory of the checkout.
func locateDiffPath(root, path string, deleted bool) string {
	for dir := root; ; dir = filepath.Dir(dir) {
		candidate := filepath.Join(dir, filepath.FromSlash(path))
		target := candidate
		if deleted {
			target = filepath.Dir(candidate)
		}
		if _, err := os.Stat(target); err == nil {
			return candidate
		}
		if filepath.Dir(dir) == dir {
			return filepath.Join(root, filepath.FromSlash(path))
		}
	}
}
