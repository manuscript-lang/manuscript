package cli

import (
	"errors"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"strings"

	"github.com/manuscript-lang/manuscript/pkg/project"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

type formatResult struct {
	Format      int                 `json:"format"`
	Files       []formatFileResult  `json:"files"`
	Diagnostics []commandDiagnostic `json:"diagnostics"`
}

type formatFileResult struct {
	Path   string `json:"path"`
	Status string `json:"status"`
}

type formatDrift struct{ path string }

func (e formatDrift) Error() string {
	return fmt.Sprintf("Formatting needed: %s; run ms fmt %s to rewrite it", e.path, e.path)
}

type formatSourceError struct {
	path string
	err  error
}

func (e formatSourceError) Error() string {
	return fmt.Sprintf("%v\nfmt only formats source that parses; fix the syntax error above, then re-run ms fmt %s", e.err, e.path)
}
func (e formatSourceError) Unwrap() error { return e.err }

// Display uses physical identity for both explicit and discovered targets.
// Outside the invocation directory (or across Windows volumes) it stays absolute.
func formatDisplay(cwd, path string) string {
	absolute, err := filepath.Abs(path)
	if err != nil {
		return filepath.Clean(path)
	}
	if physical, err := filepath.EvalSymlinks(absolute); err == nil {
		absolute = physical
	}
	if relative, err := filepath.Rel(cwd, absolute); err == nil && relative != ".." && !strings.HasPrefix(relative, ".."+string(filepath.Separator)) {
		if strings.HasPrefix(relative, "-") {
			return "." + string(filepath.Separator) + relative
		}
		return relative
	}
	return absolute
}

func formatError(cwd, target string, err error) (commandDiagnostic, string) {
	display := formatDisplay(cwd, target)
	var source syntax.Diagnostic
	if errors.As(err, &source) {
		return sourceDiagnostic(source), err.Error()
	}
	var manifest *project.ManifestError
	if errors.As(err, &manifest) {
		location := manifest.Location
		location.File = display
		issue := syntax.Diagnostic{Position: syntax.Position{File: display, Line: location.Line, Column: location.Column, Offset: location.Offset}, Phase: "resolution", Message: manifest.Cause.Error()}
		return sourceDiagnostic(issue), (&project.ManifestError{Location: location, Cause: manifest.Cause}).Error()
	}
	code := "MSF002"
	var drift formatDrift
	if errors.As(err, &drift) {
		code = "MSF001"
	}
	message := err.Error()
	var pathError *fs.PathError
	if errors.As(err, &pathError) {
		copy := *pathError
		copy.Path = formatDisplay(cwd, pathError.Path)
		display = copy.Path
		message = fileError(&copy)
	}
	return commandDiagnostic{Code: code, Phase: "format", Message: message, Position: syntax.Position{File: display, Line: 1, Column: 1}}, message
}

func formatCWD() (string, error) {
	cwd, err := os.Getwd()
	if err != nil {
		return "", err
	}
	return filepath.EvalSymlinks(cwd)
}
