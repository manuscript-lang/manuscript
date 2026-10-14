package debugger

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"

	"github.com/go-delve/delve/service/api"
	"github.com/manuscript-lang/manuscript/pkg/build"
	"github.com/manuscript-lang/manuscript/pkg/stdlib"
	"github.com/manuscript-lang/manuscript/pkg/tooling"
)

type sourceView struct {
	root        string
	inspection  tooling.Inspection
	locals      map[string]tooling.Local
	files       map[string]string
	recordTypes map[string]string
}

// Read the artifact's existing metadata, checking the same identities as the
// editor adapter. Never render changed source as if it described the executable.
func loadSourceView(executable string, inspection tooling.Inspection) (*sourceView, error) {
	data, err := os.ReadFile(executable + ".ms-build.json")
	if err != nil {
		return nil, err
	}
	var metadata build.BuildMetadata
	if err := json.Unmarshal(data, &metadata); err != nil {
		return nil, err
	}
	checkData := func(path string, data []byte, want string) error {
		sum := sha256.Sum256(data)
		if hex.EncodeToString(sum[:]) != want {
			return fmt.Errorf("file changed since debug build: %s", path)
		}
		return nil
	}
	check := func(path, want string) error {
		data, err := os.ReadFile(path)
		if err != nil {
			return err
		}
		return checkData(path, data, want)
	}
	if !metadata.Debug || metadata.SourceRoot == "" || inspection.Format != 1 {
		return nil, fmt.Errorf("script debugging requires Debug metadata and format 1 inspection")
	}
	if err := check(executable, metadata.ExecutableSHA256); err != nil {
		return nil, err
	}
	v := &sourceView{root: metadata.SourceRoot, inspection: inspection, locals: map[string]tooling.Local{}, files: map[string]string{}, recordTypes: map[string]string{}}
	if hash, ok := metadata.Sources["ms.toml"]; ok {
		if err := check(filepath.Join(v.root, "ms.toml"), hash); err != nil {
			return nil, err
		}
	}
	for _, source := range inspection.Sources {
		path := filepath.Clean(filepath.Join(v.root, filepath.FromSlash(source.File)))
		if metadata.Sources[source.File] != source.SHA256 {
			return nil, fmt.Errorf("inspection does not match debug source: %s", source.File)
		}
		if standard, ok := strings.CutPrefix(source.File, "@std/"); ok {
			data, err := stdlib.Sources.ReadFile(standard)
			if err != nil {
				return nil, fmt.Errorf("read pinned source %s: %w", source.File, err)
			}
			if err := checkData(source.File, data, source.SHA256); err != nil {
				return nil, err
			}
		} else if err := check(path, source.SHA256); err != nil {
			return nil, err
		}
		v.files[path] = source.File
	}
	for _, local := range inspection.Locals {
		v.locals[local.GoID] = local
	}
	for _, entity := range inspection.Entities {
		if entity.GoID != "" {
			v.recordTypes["record_"+entity.GoID] = entity.Name
		}
	}
	return v, nil
}

type sourceFrame struct {
	Index          int    `json:"index"` // native index, retained after filtering
	File           string `json:"file"`
	Line           int    `json:"line"`
	Function       string `json:"function"`
	NativeFunction string `json:"native_function"`
	Source         bool   `json:"source"`
}

func (v *sourceView) frame(location api.Location, index int) sourceFrame {
	native := location.Function.Name()
	f := sourceFrame{Index: index, File: location.File, Line: location.Line, Function: native, NativeFunction: native}
	file, ok := v.files[filepath.Clean(location.File)]
	if !ok || strings.Contains(native, "Cleanup") || strings.Contains(native, "Unwind") || strings.Contains(native, "Shield") {
		return f
	}
	f.File, f.Source = file, true
	// As in the editor, label closures by the enclosing declaration. Inspection
	// spans end at the header line, so use the next declaration as the boundary.
	var nearest *tooling.Entity
	for i := range v.inspection.Entities {
		e := &v.inspection.Entities[i]
		if e.Span.File == file && e.Span.Line <= f.Line && (nearest == nil || e.Span.Start > nearest.Span.Start) {
			nearest = e
		}
	}
	if nearest != nil && (nearest.Kind == "fn" || nearest.Kind == "method") {
		f.Function = nearest.Name
	}
	return f
}

// Prefer source declarations over generated Go names. Qualified file:name
// disambiguates source functions with the same spelling in different modules.
func (v *sourceView) breakpointLocation(location string) (string, error) {
	file, name, qualified := strings.Cut(location, ":")
	if !qualified {
		name = location
	}
	candidates := []tooling.Entity{}
	for _, e := range v.inspection.Entities {
		if (e.Kind == "fn" || e.Kind == "method") && e.Name == name && (!qualified || filepath.ToSlash(file) == e.Span.File) {
			candidates = append(candidates, e)
		}
	}
	if len(candidates) == 0 {
		return location, nil // file:line or an explicitly native Delve location
	}
	if len(candidates) > 1 {
		names := make([]string, len(candidates))
		for i, e := range candidates {
			names[i] = e.Span.File + ":" + e.Name
		}
		sort.Strings(names)
		return "", fmt.Errorf("ambiguous source function %q; use %s", name, strings.Join(names, ", "))
	}
	e := candidates[0]
	if e.Entry == nil {
		return "", fmt.Errorf("source function %q has no executable body entry metadata; use file:line for older inspection data", location)
	}
	return filepath.Join(v.root, filepath.FromSlash(e.Entry.File)) + ":" + strconv.Itoa(e.Entry.Line), nil
}
