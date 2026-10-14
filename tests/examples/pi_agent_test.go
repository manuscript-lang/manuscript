package examples_test

import (
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/manuscript-lang/manuscript/pkg/build"
	"github.com/manuscript-lang/manuscript/pkg/compiler"
)

// Check the actual application modules; native coverage runs their behavioral
// tests and the demo rather than maintaining a second copy of the agent.
func TestPiAgent(t *testing.T) {
	for _, example := range []struct {
		file string
		mode string
		want string
	}{
		{"test.ms", "test", ""},
		{"main.ms", "run", "Say hello\nHello from a native Manuscript tool\nDone.\n"},
	} {
		t.Run(example.file, func(t *testing.T) {
			path := filepath.Join("../../examples/pi-agent/src", example.file)
			options := compiler.Options{Tests: example.mode == "test", Entry: example.mode == "run", AnalyzeOnly: true}
			result := compiler.CompileFile(path, options)
			if !result.Success() {
				t.Fatal(result.Diagnostics)
			}
			if os.Getenv("MANUSCRIPT_EXAMPLES_NATIVE") != "1" {
				return
			}
			options.AnalyzeOnly = false
			result = compiler.CompileFile(path, options)
			if !result.Success() {
				t.Fatal(result.Diagnostics)
			}
			binary := filepath.Join(t.TempDir(), "pi-agent")
			if err := build.Build(result.Source, binary); err != nil {
				t.Fatal(err)
			}
			runExample(t, binary, example.mode, exampleRun{Stdout: example.want})
		})
	}
}

// Exercise the exported core proxy over real loopback HTTP, including blocked
// reads interrupted by cancellation. Source fakes alone cannot verify this.
func TestPiAgentProxy(t *testing.T) {
	path := "../../examples/pi-agent/src/proxy-fixture.ms"
	options := compiler.Options{Entry: true, AnalyzeOnly: true}
	result := compiler.CompileFile(path, options)
	if !result.Success() {
		t.Fatal(result.Diagnostics)
	}
	if os.Getenv("MANUSCRIPT_EXAMPLES_NATIVE") != "1" {
		return
	}
	options.AnalyzeOnly = false
	result = compiler.CompileFile(path, options)
	if !result.Success() {
		t.Fatal(result.Diagnostics)
	}
	binary := filepath.Join(t.TempDir(), "proxy-fixture")
	if err := build.Build(result.Source, binary); err != nil {
		t.Fatal(err)
	}
	for _, mode := range []string{"normal", "error", "eof", "malformed", "limit", "abort", "timeout"} {
		t.Run(mode, func(t *testing.T) {
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				if r.Method != "POST" || r.URL.Path != "/api/stream" || r.Header.Get("Authorization") != "Bearer test" {
					t.Errorf("unexpected request method, path, or authorization")
				}
				var payload map[string]any
				if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
					t.Errorf("invalid proxy payload: %v", err)
					return
				}
				model, _ := payload["model"].(map[string]any)
				options, _ := payload["options"].(map[string]any)
				context, _ := payload["context"].(map[string]any)
				if model["id"] != "fixture" || options["sessionId"] != "session" || payload["marker"] != "native" {
					t.Errorf("model, options, or payload hook lost: %v", payload)
				}
				if _, present := options["apiKey"]; present {
					t.Error("provider API key leaked into proxy payload")
				}
				if _, present := context["tools"]; present {
					t.Error("executable tools leaked into proxy context")
				}
				if mode == "error" {
					w.WriteHeader(http.StatusServiceUnavailable)
					return
				}
				w.Header().Set("Content-Type", "text/event-stream")
				w.WriteHeader(http.StatusOK)
				w.(http.Flusher).Flush()
				if mode == "abort" || mode == "timeout" {
					select {
					case <-r.Context().Done():
					case <-time.After(10 * time.Second):
						t.Error("proxy cancellation did not interrupt blocked HTTP read")
					}
					return
				}
				if mode == "malformed" {
					fmt.Fprint(w, "data: {invalid}\n\n")
					return
				}
				events := []map[string]any{
					{"type": "start"},
					{"type": "text_start", "contentIndex": 0},
					{"type": "text_delta", "contentIndex": 0, "delta": "héllo"},
					{"type": "text_end", "contentIndex": 0, "contentSignature": "sig"},
					{"type": "done", "reason": "stop", "usage": map[string]int{"input": 1, "output": 2, "totalTokens": 3}, "providerThinkingLevel": "native-level"},
				}
				if mode == "eof" {
					events = events[:len(events)-1]
				}
				for _, event := range events {
					data, _ := json.Marshal(event)
					// Deliberately split Unicode and JSON tokens across HTTP writes.
					frame := append(append([]byte("data: "), data...), '\n', '\n')
					for _, b := range frame {
						if _, err := w.Write([]byte{b}); err != nil {
							return // Limits/cancellation can close the client early.
						}
						w.(http.Flusher).Flush()
					}
				}
			}))
			defer server.Close()
			runExample(t, binary, "run", exampleRun{Args: []string{server.URL, mode}, Stdout: "proxy ok\n"})
		})
	}
}
