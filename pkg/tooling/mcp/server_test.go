package mcp

import (
	"bytes"
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/manuscript-lang/manuscript/pkg/compiler"
)

type call struct {
	dir  string
	args []string
}

// session sends newline-delimited requests and returns responses keyed by id.
func session(t *testing.T, exec Executor, requests ...string) map[int]map[string]any {
	t.Helper()
	var out bytes.Buffer
	server := &Server{Version: "test", Exec: exec}
	if err := server.Serve(context.Background(), strings.NewReader(strings.Join(requests, "\n")+"\n"), &out); err != nil {
		t.Fatal(err)
	}
	responses := map[int]map[string]any{}
	for _, line := range strings.Split(strings.TrimSpace(out.String()), "\n") {
		var message map[string]any
		if err := json.Unmarshal([]byte(line), &message); err != nil {
			t.Fatalf("bad response %q: %v", line, err)
		}
		if id, ok := message["id"].(float64); ok {
			responses[int(id)] = message
		}
	}
	return responses
}

func callRequest(id int, name, arguments string) string {
	return `{"jsonrpc":"2.0","id":` + string(rune('0'+id)) + `,"method":"tools/call","params":{"name":"` + name + `","arguments":` + arguments + `}}`
}

func toolText(t *testing.T, response map[string]any) (string, bool) {
	t.Helper()
	result, ok := response["result"].(map[string]any)
	if !ok {
		t.Fatalf("no result: %v", response)
	}
	content := result["content"].([]any)[0].(map[string]any)
	return content["text"].(string), result["isError"].(bool)
}

func TestInitializeNegotiatesAndAdvertisesCapabilities(t *testing.T) {
	r := session(t, nil,
		`{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05"}}`,
		`{"jsonrpc":"2.0","method":"notifications/initialized"}`,
		`{"jsonrpc":"2.0","id":2,"method":"initialize","params":{"protocolVersion":"1999-01-01"}}`,
		`{"jsonrpc":"2.0","id":3,"method":"ping"}`,
		`{"jsonrpc":"2.0","id":4,"method":"nope"}`)
	first := r[1]["result"].(map[string]any)
	if first["protocolVersion"] != "2024-11-05" || first["serverInfo"].(map[string]any)["version"] != "test" {
		t.Errorf("initialize = %v", first)
	}
	if r[2]["result"].(map[string]any)["protocolVersion"] != supportedVersions[0] {
		t.Errorf("unknown version should get the newest: %v", r[2])
	}
	if r[3]["result"] == nil || r[4]["error"].(map[string]any)["code"].(float64) != codeMethodNotFound {
		t.Errorf("ping/unknown = %v %v", r[3], r[4])
	}
	if len(r) != 4 {
		t.Errorf("notification got a response: %v", r)
	}
}

func TestMalformedInputGetsParseError(t *testing.T) {
	var out bytes.Buffer
	server := &Server{}
	_ = server.Serve(context.Background(), strings.NewReader("not json\n"), &out)
	if !strings.Contains(out.String(), `"code":-32700`) {
		t.Errorf("response = %s", out.String())
	}
}

func TestToolsListMatchesHandlers(t *testing.T) {
	r := session(t, nil, `{"jsonrpc":"2.0","id":1,"method":"tools/list"}`)
	listed := r[1]["result"].(map[string]any)["tools"].([]any)
	want := []string{"check", "lint", "fmt", "test", "run", "build", "std_lookup", "symbol_info", "inspect"}
	if len(listed) != len(want) {
		t.Fatalf("tools = %d, want %d", len(listed), len(want))
	}
	for i, name := range want {
		tool := listed[i].(map[string]any)
		if tool["name"] != name || tool["description"] == "" || tool["inputSchema"].(map[string]any)["type"] != "object" {
			t.Errorf("tool %d = %v", i, tool)
		}
	}
}

func TestExecutionToolsAcceptOnlyProjects(t *testing.T) {
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, "ms.toml"), []byte("name = \"x\"\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "main.ms"), []byte("export fn main() -> Int:\n    return 0\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	empty := t.TempDir()
	var calls []call
	exec := func(_ context.Context, workdir string, args []string, _ time.Duration) (Output, error) {
		calls = append(calls, call{workdir, args})
		return Output{Stdout: "{\"format\":1}", Code: 0}, nil
	}
	r := session(t, exec,
		callRequest(1, "run", `{"project":`+quote(filepath.Join(dir, "main.ms"))+`}`),
		callRequest(2, "test", `{"project":`+quote(empty)+`}`),
		callRequest(3, "build", `{}`),
		callRequest(4, "run", `{"project":`+quote(dir)+`,"args":["--evil"]}`),
		callRequest(5, "test", `{"project":`+quote(dir)+`,"filter":"add","timeout":5000}`),
	)
	for _, id := range []int{1, 2, 3, 4} {
		if _, failed := toolText(t, r[id]); !failed {
			t.Errorf("call %d should have been rejected: %v", id, r[id])
		}
	}
	if len(calls) != 1 {
		t.Fatalf("only the valid test call may execute, got %v", calls)
	}
	got := strings.Join(calls[0].args, " ")
	manifest := filepath.Join(dir, "ms.toml")
	if calls[0].dir != dir || !strings.HasPrefix(got, "test "+manifest+" --json --timeout 600s") || !strings.HasSuffix(got, "--filter add") {
		t.Errorf("test invocation = %s in %s", got, calls[0].dir)
	}
}

func TestRunReportsExitCodeOutputAndTimeout(t *testing.T) {
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, "ms.toml"), []byte(""), 0o644); err != nil {
		t.Fatal(err)
	}
	outputs := []Output{{Stdout: "hi\n", Stderr: "warn\n", Code: 3}, {TimedOut: true, Code: -1}}
	exec := func(context.Context, string, []string, time.Duration) (Output, error) {
		next := outputs[0]
		outputs = outputs[1:]
		return next, nil
	}
	r := session(t, exec, callRequest(1, "run", `{"project":`+quote(dir)+`}`), callRequest(2, "run", `{"project":`+quote(dir)+`,"timeout":2}`))
	text, failed := toolText(t, r[1])
	if failed || !strings.Contains(text, "exit 3") || !strings.Contains(text, "hi") || !strings.Contains(text, "warn") {
		t.Errorf("run = %q", text)
	}
	text, _ = toolText(t, r[2])
	if !strings.Contains(text, "stopped after 2 seconds") {
		t.Errorf("timeout = %q", text)
	}
}

func TestAnalysisToolsNeedExactlyOneInput(t *testing.T) {
	exec := func(context.Context, string, []string, time.Duration) (Output, error) {
		return Output{Stdout: "{\"format\":1,\"diagnostics\":[]}", Code: 1}, nil
	}
	r := session(t, exec,
		callRequest(1, "check", `{}`),
		callRequest(2, "check", `{"paths":["a.ms"],"source":"x"}`),
		callRequest(3, "check", `{"source":"export fn main() -> Int:\n    return 0\n"}`),
		callRequest(4, "lint", `{"paths":["-evil.ms"]}`))
	for _, id := range []int{1, 2} {
		if _, failed := toolText(t, r[id]); !failed {
			t.Errorf("call %d should fail", id)
		}
	}
	for _, id := range []int{3, 4} {
		if text, failed := toolText(t, r[id]); failed || !strings.Contains(text, "ok: no diagnostics") {
			t.Errorf("call %d = %q %v", id, text, failed)
		}
	}
}

func TestFormatSourceNeedsNoSubprocess(t *testing.T) {
	r := session(t, func(context.Context, string, []string, time.Duration) (Output, error) {
		t.Error("fmt source must not start a subprocess")
		return Output{}, nil
	}, callRequest(1, "fmt", `{"source":"fn  add(a:Int,b:Int)->Int:\n    return a+b\n"}`))
	text, failed := toolText(t, r[1])
	if failed || !strings.Contains(text, "fn add(a: Int, b: Int) -> Int:") {
		t.Errorf("fmt = %q", text)
	}
}

func TestStdLookupTool(t *testing.T) {
	r := session(t, nil, callRequest(1, "std_lookup", `{"query":"jsn parse","limit":2}`), callRequest(2, "std_lookup", `{"query":""}`))
	if text, failed := toolText(t, r[1]); failed || !strings.Contains(text, "@std/json.ms") || !strings.Contains(text, "fn parse") || strings.Contains(text, "```") {
		t.Errorf("lookup = %q", text)
	}
	if _, failed := toolText(t, r[2]); !failed {
		t.Error("empty query should fail")
	}
}

func TestPromptsAndResources(t *testing.T) {
	r := session(t, nil,
		`{"jsonrpc":"2.0","id":1,"method":"prompts/list"}`,
		`{"jsonrpc":"2.0","id":2,"method":"prompts/get","params":{"name":"manuscript_cheatsheet"}}`,
		`{"jsonrpc":"2.0","id":3,"method":"prompts/get","params":{"name":"write_idiomatic_manuscript","arguments":{"task":"sum a list"}}}`,
		`{"jsonrpc":"2.0","id":4,"method":"prompts/get","params":{"name":"write_idiomatic_manuscript"}}`,
		`{"jsonrpc":"2.0","id":5,"method":"resources/read","params":{"uri":"manuscript://stdlib/json"}}`,
		`{"jsonrpc":"2.0","id":6,"method":"resources/read","params":{"uri":"manuscript://nope"}}`,
		`{"jsonrpc":"2.0","id":7,"method":"resources/list"}`,
		`{"jsonrpc":"2.0","id":8,"method":"resources/read","params":{"uri":"manuscript://stdlib"}}`)
	if n := len(r[1]["result"].(map[string]any)["prompts"].([]any)); n != 3 {
		t.Errorf("prompts = %d", n)
	}
	promptText := func(id int) string {
		return r[id]["result"].(map[string]any)["messages"].([]any)[0].(map[string]any)["content"].(map[string]any)["text"].(string)
	}
	if !strings.Contains(promptText(2), "Manuscript rules") || !strings.Contains(promptText(3), "sum a list") {
		t.Error("prompt text missing")
	}
	if r[4]["error"] == nil || r[6]["error"] == nil {
		t.Error("missing argument and unknown resource must fail")
	}
	content := r[5]["result"].(map[string]any)["contents"].([]any)[0].(map[string]any)["text"].(string)
	if !strings.Contains(content, "# @std/json.ms") {
		t.Errorf("resource = %.80q", content)
	}
	index := r[8]["result"].(map[string]any)["contents"].([]any)[0].(map[string]any)["text"].(string)
	if !strings.Contains(index, "@std/fs.ms") || !strings.Contains(index, "prelude") {
		t.Error("stdlib index incomplete")
	}
	if n := len(r[7]["result"].(map[string]any)["resources"].([]any)); n < 20 {
		t.Errorf("resources = %d", n)
	}
}

// The cheat sheet's complete program is the one claim a reader can copy verbatim.
func TestCheatsheetProgramChecks(t *testing.T) {
	_, after, found := strings.Cut(cheatsheet, "<!-- complete -->\n```manuscript\n")
	if !found {
		t.Fatal("cheat sheet lost its complete program")
	}
	source, _, _ := strings.Cut(after, "```")
	result := compiler.CompileSource("cheatsheet.ms", source, compiler.Options{Entry: true, Tests: true, AnalyzeOnly: true})
	for _, issue := range result.Diagnostics {
		t.Errorf("cheat sheet program: %v", issue)
	}
}

func quote(s string) string {
	data, _ := json.Marshal(s)
	return string(data)
}

// Agents rediscover prompts and tool schemas every session, so keep them short.
func TestDiscoveredTextStaysSmall(t *testing.T) {
	for _, p := range prompts {
		text, err := p.build(map[string]string{"task": "x", "diagnostic": "x"})
		if err != nil || len(text) > 800 {
			t.Errorf("prompt %s: %d bytes, %v", p.Name, len(text), err)
		}
	}
	data, err := json.Marshal(toolDefinitions())
	if err != nil || len(data) > 2800 {
		t.Errorf("tools/list is %d bytes, %v", len(data), err)
	}
	for _, tl := range tools {
		if len(tl.Description) > 130 {
			t.Errorf("tool %s description is %d bytes", tl.Name, len(tl.Description))
		}
	}
	if len(instructions) > 260 {
		t.Errorf("instructions are %d bytes", len(instructions))
	}
}

func TestSymbolInfoTool(t *testing.T) {
	path := filepath.Join(t.TempDir(), "main.ms")
	source := "fn double(value: Int) -> Int:\n    return value * 2\n\nexport fn main() -> Int:\n    return double(4) - 8\n"
	if err := os.WriteFile(path, []byte(source), 0o644); err != nil {
		t.Fatal(err)
	}
	r := session(t, nil, callRequest(1, "symbol_info", `{"path":`+quote(path)+`,"line":5,"column":12}`), callRequest(2, "symbol_info", `{"path":`+quote(path)+`,"line":0,"column":1}`))
	text, failed := toolText(t, r[1])
	if failed || !strings.Contains(text, "type: ") || !strings.Contains(text, "defined: ") || !strings.Contains(text, "references (2)") {
		t.Errorf("symbol_info = %q", text)
	}
	if _, failed := toolText(t, r[2]); !failed {
		t.Error("line 0 should fail")
	}
}

func TestCompactReportsShowOnlyWhatNeedsAction(t *testing.T) {
	passing := `{"tests":[{"name":"a","status":"passed"}],"summary":{"selected":1,"passed":1},"completed":true,"diagnostics":[]}`
	if got := testReport(passing); got != "1 passed, 0 failed" {
		t.Errorf("passing = %q", got)
	}
	failing := `{"tests":[{"name":"t::x","status":"failed","failure":"expected 3, got 2"},{"name":"t::y","status":"passed"}],"summary":{"passed":1,"failed":1},"completed":true,"diagnostics":[]}`
	if got := testReport(failing); got != "1 passed, 1 failed\nFAIL t::x: expected 3, got 2" {
		t.Errorf("failing = %q", got)
	}
	var many strings.Builder
	many.WriteString(`{"diagnostics":[`)
	for i := 0; i < 100; i++ {
		if i > 0 {
			many.WriteString(",")
		}
		many.WriteString(`{"code":"MS1","message":"m","position":{"file":"f.ms","line":1,"column":1}}`)
	}
	many.WriteString("]}")
	got := diagnosticsReport(many.String())
	if lines := strings.Count(got, "\n"); lines > maxLines+2 || !strings.Contains(got, "... 60 more") {
		t.Errorf("diagnostics not capped: %d lines", lines)
	}
	if got := buildReport(`{"completed":true,"exit_code":0,"output":"/tmp/x","diagnostics":[]}`); got != "ok: built /tmp/x" {
		t.Errorf("build = %q", got)
	}
	if got := formatReport(`{"files":[{"path":"a.ms","status":"clean"},{"path":"b.ms","status":"needs_formatting"}],"diagnostics":[{"code":"MSF001","message":"x","position":{}}]}`); !strings.Contains(got, "b.ms") || strings.Contains(got, "a.ms") || strings.Contains(got, "MSF001") {
		t.Errorf("format = %q", got)
	}
	if got := clip(strings.Repeat("x", 20000), 1000); len(got) > 1100 || !strings.Contains(got, "omitted") {
		t.Errorf("clip = %d bytes", len(got))
	}
}

func TestSlowToolsReportProgress(t *testing.T) {
	old := progressInterval
	progressInterval = 10 * time.Millisecond
	defer func() { progressInterval = old }()
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, "ms.toml"), nil, 0o644); err != nil {
		t.Fatal(err)
	}
	slow := func(context.Context, string, []string, time.Duration) (Output, error) {
		time.Sleep(80 * time.Millisecond)
		return Output{}, nil
	}
	var out bytes.Buffer
	server := &Server{Exec: slow}
	request := `{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"run","arguments":{"project":` + quote(dir) + `},"_meta":{"progressToken":"p1"}}}` + "\n"
	if err := server.Serve(context.Background(), strings.NewReader(request), &out); err != nil {
		t.Fatal(err)
	}
	if strings.Count(out.String(), `"notifications/progress"`) < 2 || !strings.Contains(out.String(), `"progressToken":"p1"`) {
		t.Errorf("no progress in %s", out.String())
	}
	out.Reset()
	request = strings.Replace(request, `,"_meta":{"progressToken":"p1"}`, "", 1)
	_ = (&Server{Exec: slow}).Serve(context.Background(), strings.NewReader(request), &out)
	if strings.Contains(out.String(), "progress") {
		t.Error("progress sent without a token")
	}
}

func TestBuildKeepsTheBinaryInTheIgnoredCache(t *testing.T) {
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, "ms.toml"), nil, 0o644); err != nil {
		t.Fatal(err)
	}
	var args []string
	exec := func(_ context.Context, _ string, a []string, _ time.Duration) (Output, error) {
		args = a
		return Output{Stdout: `{"completed":true,"exit_code":0,"output":"` + a[len(a)-1] + `","diagnostics":[]}`}, nil
	}
	r := session(t, exec, callRequest(1, "build", `{"project":`+quote(dir)+`}`))
	text, failed := toolText(t, r[1])
	want := filepath.Join(dir, ".ms-cache", "bin")
	if failed || !strings.HasPrefix(text, "ok: built "+want) || !strings.HasPrefix(args[len(args)-1], want) {
		t.Errorf("build = %q (%v), args %v", text, failed, args)
	}
	if info, err := os.Stat(want); err != nil || !info.IsDir() {
		t.Errorf("output directory missing: %v", err)
	}
}
