package mcp

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"time"

	"github.com/manuscript-lang/manuscript/pkg/tooling"
	"github.com/manuscript-lang/manuscript/pkg/tooling/lsp"
)

type tool struct {
	Name        string         `json:"name"`
	Description string         `json:"description"`
	InputSchema map[string]any `json:"inputSchema"`
	Annotations map[string]any `json:"annotations,omitempty"`
	handler     func(*Server, context.Context, json.RawMessage) (string, error)
	slow        bool // reports progress while a build or run is in flight
}

// toolError is a failure the agent can act on; it becomes an isError result.
type toolError string

func (e toolError) Error() string { return string(e) }

func obj(required []string, properties map[string]any) map[string]any {
	schema := map[string]any{"type": "object", "properties": properties}
	if len(required) > 0 {
		schema["required"] = required
	}
	return schema
}

func pathList() map[string]any {
	return map[string]any{"type": "array", "items": map[string]any{"type": "string"}}
}

func seconds() map[string]any {
	return map[string]any{"type": "integer", "description": "seconds"}
}

func readOnly() map[string]any { return map[string]any{"readOnlyHint": true} }

var tools = []tool{
	{
		Name:        "check",
		Description: "Type-check without running. Diagnostics read '<cause>; <fix>'. Pass paths (files, dirs, ms.toml) or source.",
		InputSchema: obj(nil, map[string]any{"paths": pathList(), "source": map[string]any{"type": "string"}}),
		Annotations: readOnly(),
		handler: func(s *Server, ctx context.Context, raw json.RawMessage) (string, error) {
			return s.analyze(ctx, "check", raw)
		},
	},
	{
		Name:        "lint",
		Description: "Lint rules with stable codes. Pass paths or source.",
		InputSchema: obj(nil, map[string]any{"paths": pathList(), "source": map[string]any{"type": "string"}}),
		Annotations: readOnly(),
		handler: func(s *Server, ctx context.Context, raw json.RawMessage) (string, error) {
			return s.analyze(ctx, "lint", raw)
		},
	},
	{
		Name:        "fmt",
		Description: "source: returns formatted text. paths: lists unformatted files, or rewrites them when write is true.",
		InputSchema: obj(nil, map[string]any{"source": map[string]any{"type": "string"}, "paths": pathList(), "write": map[string]any{"type": "boolean"}}),
		handler:     (*Server).format,
	},
	{
		Name:        "test",
		Description: "Run a project's tests; returns failures only. Project (ms.toml or its directory) only.",
		InputSchema: obj([]string{"project"}, map[string]any{"project": map[string]any{"type": "string"}, "filter": map[string]any{"type": "string"}, "timeout": seconds()}),
		handler:     (*Server).test,
		slow:        true,
	},
	{
		Name:        "run",
		Description: "Build and run a project's main. Project only; no arguments or stdin.",
		InputSchema: obj([]string{"project"}, map[string]any{"project": map[string]any{"type": "string"}, "timeout": seconds()}),
		handler:     (*Server).run,
		slow:        true,
	},
	{
		Name:        "build",
		Description: "Build a project natively; returns the binary path (in .ms-cache/bin). Project only.",
		InputSchema: obj([]string{"project"}, map[string]any{"project": map[string]any{"type": "string"}, "timeout": seconds()}),
		handler:     (*Server).build,
		slow:        true,
	},
	{
		Name:        "search_stdlib",
		Description: "Fuzzy-search the standard library (typos, loose words). Use before calling any std API. Example: query \"read file lines\".",
		InputSchema: obj([]string{"query"}, map[string]any{"query": map[string]any{"type": "string"}, "limit": map[string]any{"type": "integer"}}),
		Annotations: readOnly(),
		handler:     (*Server).searchStdlib,
	},
	{
		Name:        "symbol_info",
		Description: "Type, definition, and references of the symbol at a 1-based line and column.",
		InputSchema: obj([]string{"path", "line", "column"}, map[string]any{"path": map[string]any{"type": "string"}, "line": map[string]any{"type": "integer"}, "column": map[string]any{"type": "integer"}}),
		Annotations: readOnly(),
		handler:     (*Server).symbolInfo,
	},
	{
		Name:        "inspect",
		Description: "List a file's or project's declarations with types and locations.",
		InputSchema: obj([]string{"path"}, map[string]any{"path": map[string]any{"type": "string"}}),
		Annotations: readOnly(),
		handler:     (*Server).inspect,
	},
}

func toolDefinitions() []tool { return tools }

func (s *Server) callTool(ctx context.Context, params json.RawMessage) (any, *rpcError) {
	var p struct {
		Name      string          `json:"name"`
		Arguments json.RawMessage `json:"arguments"`
		Meta      struct {
			ProgressToken json.RawMessage `json:"progressToken"`
		} `json:"_meta"`
	}
	if err := json.Unmarshal(params, &p); err != nil {
		return nil, &rpcError{codeInvalidParams, "invalid tools/call parameters: " + err.Error()}
	}
	for _, t := range tools {
		if t.Name != p.Name {
			continue
		}
		if len(p.Arguments) == 0 {
			p.Arguments = json.RawMessage("{}")
		}
		if t.slow {
			defer s.reportProgress(p.Meta.ProgressToken, p.Name)()
		}
		text, err := t.handler(s, ctx, p.Arguments)
		if err != nil {
			return toolResult(err.Error(), true), nil
		}
		return toolResult(text, false), nil
	}
	return nil, &rpcError{codeInvalidParams, "unknown tool " + p.Name}
}

func toolResult(text string, failed bool) map[string]any {
	return map[string]any{"content": []map[string]any{{"type": "text", "text": clip(text, 12000)}}, "isError": failed}
}

func decode(raw json.RawMessage, into any) error {
	decoder := json.NewDecoder(bytes.NewReader(raw))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(into); err != nil {
		return toolError("invalid arguments: " + err.Error())
	}
	return nil
}

func (s *Server) exec(ctx context.Context, dir string, timeout time.Duration, args ...string) (Output, error) {
	run := s.Exec
	if run == nil {
		run = SelfExecutor
	}
	out, err := run(ctx, dir, args, timeout)
	if err != nil {
		return out, toolError("could not start ms: " + err.Error())
	}
	return out, nil
}

// withSource writes a snippet to a private directory so the CLI can check it as main.ms.
func withSource(source string, use func(dir string) (string, error)) (string, error) {
	dir, err := os.MkdirTemp("", "ms-mcp-")
	if err != nil {
		return "", toolError(err.Error())
	}
	defer os.RemoveAll(dir)
	if err := os.WriteFile(filepath.Join(dir, "main.ms"), []byte(source), 0o600); err != nil {
		return "", toolError(err.Error())
	}
	return use(dir)
}

func absolutePaths(paths []string) ([]string, error) {
	out := make([]string, 0, len(paths))
	for _, p := range paths {
		if p == "" {
			return nil, toolError("a path is empty; pass a .ms file, directory, or ms.toml")
		}
		abs, err := filepath.Abs(p)
		if err != nil {
			return nil, toolError(err.Error())
		}
		out = append(out, abs)
	}
	return out, nil
}

// reported renders a command's JSON report with format. Exit status 1 with a
// report means findings were found, which is a normal result; anything else is
// a failure to relay.
func reported(out Output, format func(string) string) (string, error) {
	if out.TimedOut {
		return "", toolError("timed out")
	}
	if strings.TrimSpace(out.Stdout) != "" && out.Code <= 1 {
		return format(out.Stdout) + truncationNote(out), nil
	}
	return "", toolError(clip(strings.TrimSpace(out.Stderr+out.Stdout), maxText))
}

func truncationNote(out Output) string {
	if out.Truncated {
		return "\n[output truncated]"
	}
	return ""
}

func (s *Server) analyze(ctx context.Context, command string, raw json.RawMessage) (string, error) {
	var in struct {
		Paths  []string `json:"paths"`
		Source *string  `json:"source"`
	}
	if err := decode(raw, &in); err != nil {
		return "", err
	}
	if (len(in.Paths) == 0) == (in.Source == nil) {
		return "", toolError("pass exactly one of paths or source")
	}
	if in.Source != nil {
		return withSource(*in.Source, func(dir string) (string, error) {
			out, err := s.exec(ctx, dir, time.Minute, command, "main.ms", "--json")
			if err != nil {
				return "", err
			}
			return reported(out, diagnosticsReport)
		})
	}
	paths, err := absolutePaths(in.Paths)
	if err != nil {
		return "", err
	}
	out, err := s.exec(ctx, "", 2*time.Minute, append([]string{command}, append(paths, "--json")...)...)
	if err != nil {
		return "", err
	}
	return reported(out, diagnosticsReport)
}

func (s *Server) format(ctx context.Context, raw json.RawMessage) (string, error) {
	var in struct {
		Source *string  `json:"source"`
		Paths  []string `json:"paths"`
		Write  bool     `json:"write"`
	}
	if err := decode(raw, &in); err != nil {
		return "", err
	}
	if (len(in.Paths) == 0) == (in.Source == nil) {
		return "", toolError("pass exactly one of paths or source")
	}
	if in.Source != nil {
		formatted, err := tooling.Format("main.ms", *in.Source)
		if err != nil {
			return "", toolError(err.Error())
		}
		return formatted, nil
	}
	paths, err := absolutePaths(in.Paths)
	if err != nil {
		return "", err
	}
	args := append([]string{"fmt"}, paths...)
	if !in.Write {
		args = append(args, "--check", "--json")
	}
	out, err := s.exec(ctx, "", 2*time.Minute, args...)
	if err != nil {
		return "", err
	}
	if in.Write {
		if out.Code != 0 {
			return "", toolError(strings.TrimSpace(out.Stderr + out.Stdout))
		}
		return "ok: formatted", nil
	}
	return reported(out, formatReport)
}

// project resolves an ms.toml. Execution tools take nothing else: the manifest
// decides the entry, tests, and pins, so no caller picks arbitrary code to run.
func project(p string) (manifest, dir string, err error) {
	if p == "" {
		return "", "", toolError("project is required: pass an ms.toml or the directory containing it")
	}
	abs, err := filepath.Abs(p)
	if err != nil {
		return "", "", toolError(err.Error())
	}
	info, err := os.Stat(abs)
	if err != nil {
		return "", "", toolError("project not found: " + p + "; check the path")
	}
	if info.IsDir() {
		abs = filepath.Join(abs, "ms.toml")
		if _, err := os.Stat(abs); err != nil {
			return "", "", toolError("no ms.toml in " + p + "; pass the project directory or its ms.toml")
		}
	}
	if filepath.Base(abs) != "ms.toml" {
		return "", "", toolError("only a project is accepted here: pass ms.toml or its directory, not " + filepath.Base(abs))
	}
	return abs, filepath.Dir(abs), nil
}

func clampSeconds(value, fallback, ceiling int) time.Duration {
	if value <= 0 {
		value = fallback
	}
	return time.Duration(min(value, ceiling)) * time.Second
}

func (s *Server) test(ctx context.Context, raw json.RawMessage) (string, error) {
	var in struct {
		Project string `json:"project"`
		Filter  string `json:"filter"`
		Timeout int    `json:"timeout"`
	}
	if err := decode(raw, &in); err != nil {
		return "", err
	}
	manifest, dir, err := project(in.Project)
	if err != nil {
		return "", err
	}
	timeout := clampSeconds(in.Timeout, 120, 600)
	args := []string{"test", manifest, "--json", "--timeout", fmt.Sprintf("%ds", int(timeout.Seconds()))}
	if in.Filter != "" {
		args = append(args, "--filter", in.Filter)
	}
	out, err := s.exec(ctx, dir, timeout+10*time.Second, args...)
	if err != nil {
		return "", err
	}
	if out.TimedOut {
		return "", toolError(fmt.Sprintf("test run stopped after %d seconds", int(timeout.Seconds())))
	}
	text, err := reported(out, testReport)
	if err != nil {
		return "", err
	}
	if strings.TrimSpace(out.Stderr) != "" {
		text += "\nstderr:\n" + clip(strings.TrimRight(out.Stderr, "\n"), 1500)
	}
	return text, nil
}

func (s *Server) run(ctx context.Context, raw json.RawMessage) (string, error) {
	var in struct {
		Project string `json:"project"`
		Timeout int    `json:"timeout"`
	}
	if err := decode(raw, &in); err != nil {
		return "", err
	}
	manifest, dir, err := project(in.Project)
	if err != nil {
		return "", err
	}
	timeout := clampSeconds(in.Timeout, 30, 300)
	out, err := s.exec(ctx, dir, timeout, "run", manifest)
	if err != nil {
		return "", err
	}
	var b strings.Builder
	if out.TimedOut {
		fmt.Fprintf(&b, "stopped after %d seconds", int(timeout.Seconds()))
	} else {
		fmt.Fprintf(&b, "exit %d", out.Code)
	}
	if text := strings.TrimRight(out.Stdout, "\n"); text != "" {
		b.WriteString("\nstdout:\n" + clip(text, 4000))
	}
	if text := strings.TrimRight(out.Stderr, "\n"); text != "" {
		b.WriteString("\nstderr:\n" + clip(text, 2000))
	}
	b.WriteString(truncationNote(out))
	return b.String(), nil
}

func (s *Server) build(ctx context.Context, raw json.RawMessage) (string, error) {
	var in struct {
		Project string `json:"project"`
		Timeout int    `json:"timeout"`
	}
	if err := decode(raw, &in); err != nil {
		return "", err
	}
	manifest, dir, err := project(in.Project)
	if err != nil {
		return "", err
	}
	// .ms-cache is where `ms init` already tells git to ignore build output.
	// Clearing it first keeps exactly one binary, and a failed build cannot
	// leave a stale one behind.
	directory := filepath.Join(dir, ".ms-cache", "bin")
	if err := os.RemoveAll(directory); err != nil {
		return "", toolError(err.Error())
	}
	if err := os.MkdirAll(directory, 0o755); err != nil {
		return "", toolError(err.Error())
	}
	name := "program"
	if runtime.GOOS == "windows" {
		name += ".exe"
	}
	out, err := s.exec(ctx, dir, clampSeconds(in.Timeout, 300, 600), "build", manifest, "--json", "-o", filepath.Join(directory, name))
	if err != nil {
		return "", err
	}
	return reported(out, buildReport)
}

func (s *Server) searchStdlib(_ context.Context, raw json.RawMessage) (string, error) {
	var in struct {
		Query string `json:"query"`
		Limit int    `json:"limit"`
	}
	if err := decode(raw, &in); err != nil {
		return "", err
	}
	if strings.TrimSpace(in.Query) == "" {
		return "", toolError("query is required")
	}
	limit := min(in.Limit, 15)
	return formatMatches(in.Query, Lookup(in.Query, limit)), nil
}

func (s *Server) inspect(ctx context.Context, raw json.RawMessage) (string, error) {
	var in struct {
		Path string `json:"path"`
	}
	if err := decode(raw, &in); err != nil {
		return "", err
	}
	paths, err := absolutePaths([]string{in.Path})
	if err != nil {
		return "", err
	}
	out, err := s.exec(ctx, "", 2*time.Minute, "inspect", paths[0], "--json")
	if err != nil {
		return "", err
	}
	return reported(out, inspectReport)
}

func (s *Server) symbolInfo(_ context.Context, raw json.RawMessage) (string, error) {
	var in struct {
		Path         string `json:"path"`
		Line, Column int
	}
	if err := decode(raw, &in); err != nil {
		return "", err
	}
	if in.Path == "" {
		return "", toolError("path is required")
	}
	info, err := lsp.QuerySymbol(in.Path, in.Line, in.Column)
	if err != nil {
		return "", toolError(err.Error())
	}
	return symbolReport(info.Hover, info.Definition, info.References, info.Diagnostics), nil
}
