package mcp

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/manuscript-lang/manuscript/pkg/tooling"
)

type tool struct {
	Name        string         `json:"name"`
	Description string         `json:"description"`
	InputSchema map[string]any `json:"inputSchema"`
	Annotations map[string]any `json:"annotations,omitempty"`
	handler     func(*Server, context.Context, json.RawMessage) (string, error)
}

// toolError is a failure the agent can act on; it becomes an isError result.
type toolError string

func (e toolError) Error() string { return string(e) }

func obj(required []string, properties map[string]any) map[string]any {
	schema := map[string]any{"type": "object", "properties": properties, "additionalProperties": false}
	if len(required) > 0 {
		schema["required"] = required
	}
	return schema
}

func str(description string) map[string]any {
	return map[string]any{"type": "string", "description": description}
}

func integer(description string) map[string]any {
	return map[string]any{"type": "integer", "description": description}
}

func pathList(description string) map[string]any {
	return map[string]any{"type": "array", "items": map[string]any{"type": "string"}, "description": description}
}

func readOnly(open bool) map[string]any {
	return map[string]any{"readOnlyHint": true, "destructiveHint": false, "idempotentHint": true, "openWorldHint": open}
}

var tools = []tool{
	{
		Name:        "check",
		Description: "Type-check without running. Returns JSON diagnostics (empty list = valid); messages read '<cause>; <fix>'. Pass paths (files, dirs, ms.toml) or source.",
		InputSchema: obj(nil, map[string]any{"paths": pathList("Files, directories, or ms.toml projects to check."), "source": str("Manuscript source to check as a standalone main.ms.")}),
		Annotations: readOnly(false),
		handler: func(s *Server, ctx context.Context, raw json.RawMessage) (string, error) {
			return s.analyze(ctx, "check", raw)
		},
	},
	{
		Name:        "lint",
		Description: "Lint rules as JSON findings with stable codes. Pass paths or source.",
		InputSchema: obj(nil, map[string]any{"paths": pathList("Files, directories, or ms.toml projects to lint."), "source": str("Manuscript source to lint as a standalone main.ms.")}),
		Annotations: readOnly(false),
		handler: func(s *Server, ctx context.Context, raw json.RawMessage) (string, error) {
			return s.analyze(ctx, "lint", raw)
		},
	},
	{
		Name:        "fmt",
		Description: "source: returns formatted text. paths: reports unformatted files, or rewrites them when write is true.",
		InputSchema: obj(nil, map[string]any{
			"source": str("Manuscript source to format; the formatted source is returned."),
			"paths":  pathList("Files, directories, or ms.toml projects to format."),
			"write":  map[string]any{"type": "boolean", "description": "Rewrite paths in place instead of only reporting. Default false."},
		}),
		Annotations: map[string]any{"readOnlyHint": false, "destructiveHint": false, "idempotentHint": true, "openWorldHint": false},
		handler:     (*Server).format,
	},
	{
		Name:        "test",
		Description: "Run a project's tests; returns JSON results. Project (ms.toml or its directory) only.",
		InputSchema: obj([]string{"project"}, map[string]any{
			"project":         str("Path to ms.toml, or the directory containing it."),
			"filter":          str("Run only tests whose module::name contains this text."),
			"timeout_seconds": integer("Stop the whole run after this many seconds. Default 120, maximum 600."),
		}),
		Annotations: map[string]any{"readOnlyHint": false, "destructiveHint": false, "openWorldHint": true},
		handler:     (*Server).test,
	},
	{
		Name:        "run",
		Description: "Build and run a project's main; returns exit code, stdout, stderr. Project (ms.toml or its directory) only; no arguments or stdin.",
		InputSchema: obj([]string{"project"}, map[string]any{
			"project":         str("Path to ms.toml, or the directory containing it."),
			"timeout_seconds": integer("Stop the program after this many seconds. Default 30, maximum 300."),
		}),
		Annotations: map[string]any{"readOnlyHint": false, "destructiveHint": false, "openWorldHint": true},
		handler:     (*Server).run,
	},
	{
		Name:        "build",
		Description: "Check that a project builds natively; returns JSON, discards the binary. Project only.",
		InputSchema: obj([]string{"project"}, map[string]any{
			"project":         str("Path to ms.toml, or the directory containing it."),
			"timeout_seconds": integer("Stop the build after this many seconds. Default 300, maximum 600."),
		}),
		Annotations: map[string]any{"readOnlyHint": false, "destructiveHint": false, "openWorldHint": false},
		handler:     (*Server).build,
	},
	{
		Name:        "std_lookup",
		Description: "Fuzzy-search the standard library (typos and loose words fine). Returns import path, signature, doc. Use before calling any std API.",
		InputSchema: obj([]string{"query"}, map[string]any{"query": str("Words describing the API, in any order."), "limit": integer("Maximum matches. Default 8, maximum 25.")}),
		Annotations: readOnly(false),
		handler:     (*Server).stdLookup,
	},
	{
		Name:        "inspect",
		Description: "Checked symbols, types and call sites of a file or project as JSON (capped).",
		InputSchema: obj([]string{"path"}, map[string]any{"path": str("A .ms file, or an ms.toml project.")}),
		Annotations: readOnly(false),
		handler:     (*Server).inspect,
	},
}

func toolDefinitions() []tool { return tools }

func (s *Server) callTool(ctx context.Context, params json.RawMessage) (any, *rpcError) {
	var p struct {
		Name      string          `json:"name"`
		Arguments json.RawMessage `json:"arguments"`
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
		text, err := t.handler(s, ctx, p.Arguments)
		if err != nil {
			return toolResult(err.Error(), true), nil
		}
		return toolResult(text, false), nil
	}
	return nil, &rpcError{codeInvalidParams, "unknown tool " + p.Name}
}

func toolResult(text string, failed bool) map[string]any {
	return map[string]any{"content": []map[string]any{{"type": "text", "text": text}}, "isError": failed}
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

// jsonOrFailure returns a command's JSON report. Exit status 1 with a report means
// findings were found, which is a normal result; anything else is a failure to relay.
func jsonOrFailure(out Output) (string, error) {
	if out.TimedOut {
		return "", toolError("timed out")
	}
	if strings.TrimSpace(out.Stdout) != "" && out.Code <= 1 {
		return strings.TrimRight(out.Stdout, "\n") + truncationNote(out), nil
	}
	return "", toolError(strings.TrimSpace(out.Stderr + out.Stdout))
}

func truncationNote(out Output) string {
	if out.Truncated {
		return "\n[output truncated at 256 KiB]"
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
			return jsonOrFailure(out)
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
	return jsonOrFailure(out)
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
		return "formatted " + strings.Join(in.Paths, ", "), nil
	}
	return jsonOrFailure(out)
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
		Timeout int    `json:"timeout_seconds"`
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
	text, err := jsonOrFailure(out)
	if err != nil {
		return "", err
	}
	if strings.TrimSpace(out.Stderr) != "" {
		text += "\n\nstderr:\n" + strings.TrimRight(out.Stderr, "\n")
	}
	return text, nil
}

func (s *Server) run(ctx context.Context, raw json.RawMessage) (string, error) {
	var in struct {
		Project string `json:"project"`
		Timeout int    `json:"timeout_seconds"`
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
		fmt.Fprintf(&b, "stopped after %d seconds\n", int(timeout.Seconds()))
	} else {
		fmt.Fprintf(&b, "exit code: %d\n", out.Code)
	}
	fmt.Fprintf(&b, "--- stdout ---\n%s\n--- stderr ---\n%s", out.Stdout, out.Stderr)
	b.WriteString(truncationNote(out))
	return b.String(), nil
}

func (s *Server) build(ctx context.Context, raw json.RawMessage) (string, error) {
	var in struct {
		Project string `json:"project"`
		Timeout int    `json:"timeout_seconds"`
	}
	if err := decode(raw, &in); err != nil {
		return "", err
	}
	manifest, dir, err := project(in.Project)
	if err != nil {
		return "", err
	}
	scratch, err := os.MkdirTemp("", "ms-mcp-build-")
	if err != nil {
		return "", toolError(err.Error())
	}
	defer os.RemoveAll(scratch)
	out, err := s.exec(ctx, dir, clampSeconds(in.Timeout, 300, 600), "build", manifest, "--json", "-o", filepath.Join(scratch, "program"))
	if err != nil {
		return "", err
	}
	return jsonOrFailure(out)
}

func (s *Server) stdLookup(_ context.Context, raw json.RawMessage) (string, error) {
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
	limit := min(in.Limit, 25)
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
	return jsonOrFailure(out)
}
