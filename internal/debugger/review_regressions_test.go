package debugger

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"io"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
	"time"

	"github.com/go-delve/delve/service/api"
	"github.com/manuscript-lang/manuscript/pkg/build"
	"github.com/manuscript-lang/manuscript/pkg/stdlib"
	"github.com/manuscript-lang/manuscript/pkg/tooling"
)

func TestScriptMapKeysPreserveLoadState(t *testing.T) {
	prefix := strings.Repeat("k", 512)
	entries := []api.Variable{}
	for _, key := range []api.Variable{
		{Type: "string", Kind: reflect.String, Value: prefix, Len: 600},
		{Type: "string", Kind: reflect.String, Value: prefix, Len: 601},
		{Type: "string", Kind: reflect.String, Unreadable: "key memory unavailable"},
	} {
		key.Name = "Key"
		entries = append(entries, api.Variable{Children: []api.Variable{key, {Name: "Value", Type: "int64", Kind: reflect.Int, Value: "42"}}})
	}
	variable := api.Variable{Type: "runtime.Map", Kind: reflect.Struct, Children: []api.Variable{{Name: "Entries", Len: 3, Children: entries}}}
	data, err := json.Marshal(renderValue(variable, "entries", "Map[String, Int]", 0, nil))
	if err != nil {
		t.Fatal(err)
	}
	var view struct {
		Truncated bool
		Children  []struct {
			Name string
			Key  *struct {
				Value, Unavailable string
				Truncated          bool
			}
		}
	}
	if err := json.Unmarshal(data, &view); err != nil {
		t.Fatal(err)
	}
	if !view.Truncated || len(view.Children) != 3 {
		t.Fatalf("map concealed incomplete keys: %s", data)
	}
	for _, child := range view.Children[:2] {
		if child.Key == nil || !child.Key.Truncated {
			t.Fatalf("truncated key lost markers: %s", data)
		}
	}
	if view.Children[2].Key == nil || view.Children[2].Key.Unavailable != "key memory unavailable" {
		t.Fatalf("unavailable key lost markers: %s", data)
	}
	if view.Children[0].Name != view.Children[1].Name {
		t.Fatal("fixture does not cover indistinguishable truncated prefixes")
	}
}

func TestScriptProcessFixture(t *testing.T) {
	if os.Getenv("MANUSCRIPT_PROCESS_FIXTURE") != "1" {
		return
	}
	_, _ = io.Copy(io.Discard, os.Stdin)
}

type delayedCloseInput struct {
	reader   io.Reader
	closed   chan struct{}
	release  chan struct{}
	readDone chan struct{}
}

func (r *delayedCloseInput) Read(data []byte) (int, error) {
	n, err := r.reader.Read(data)
	if err == io.EOF {
		<-r.readDone
		return 0, io.EOF
	}
	return n, err
}
func (r *delayedCloseInput) Close() error {
	select {
	case <-r.closed:
		return nil
	default:
		close(r.closed)
	}
	<-r.release
	close(r.readDone)
	return nil
}

func TestScriptNativeReapsBeforeClosingInput(t *testing.T) {
	executable, inspection := scriptTarget(t, "export fn main() -> Int:\n    var number = 0\n    while number == 0:\n        number = number + 0\n    return number\n")
	input := &delayedCloseInput{reader: strings.NewReader("continue\n"), closed: make(chan struct{}), release: make(chan struct{}), readDone: make(chan struct{})}
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	out := notifyWriter{commands: make(chan struct{}, 1)}
	done := make(chan int, 1)
	go func() { done <- Script(ctx, executable, nil, inspection, input, &out, false) }()
	select {
	case <-out.commands:
	case <-ctx.Done():
		t.Fatal(ctx.Err())
	}
	cancel()
	select {
	case <-input.closed:
	case <-time.After(5 * time.Second):
		t.Fatal("did not begin closing reader after cleanup")
	}
	// Close is intentionally blocked like an uncancellable console read. The
	// target must have been reaped already, even while the reader still joins.
	data := append([]byte(nil), out.Bytes()...)
	assertTargetGone(t, decodeEvents(t, data))
	close(input.release)
	select {
	case status := <-done:
		if status != 1 {
			t.Fatal(status)
		}
	case <-time.After(5 * time.Second):
		t.Fatal("did not join released reader")
	}
}

func TestScriptUnsupportedProcessIdentity(t *testing.T) {
	if scriptProcessSupported() == nil {
		return
	}
	var output bytes.Buffer
	status := Script(context.Background(), "not-launched", nil, tooling.Inspection{}, io.NopCloser(strings.NewReader("continue\n")), &output, false)
	events := decodeEvents(t, output.Bytes())
	if status != 1 || len(events) != 2 || events[0].Code != "launch" || events[0].PID != 0 || !strings.Contains(events[0].Message, "identity-bound") {
		t.Fatal(status, events)
	}
}

func TestScriptEmbeddedSourceMetadata(t *testing.T) {
	for _, name := range []string{"yaml.ms", "toml.ms"} {
		t.Run(name, func(t *testing.T) {
			root := t.TempDir()
			executable := filepath.Join(root, "program")
			if err := os.WriteFile(executable, []byte("executable identity"), 0600); err != nil {
				t.Fatal(err)
			}
			standard, err := stdlib.Sources.ReadFile(name)
			if err != nil {
				t.Fatal(err)
			}
			digest := func(data []byte) string { sum := sha256.Sum256(data); return hex.EncodeToString(sum[:]) }
			file := "@std/" + name
			metadata := build.BuildMetadata{Debug: true, SourceRoot: root, ExecutableSHA256: digest([]byte("executable identity")), Sources: map[string]string{file: digest(standard)}}
			writeMetadata := func() {
				data, err := json.Marshal(metadata)
				if err != nil {
					t.Fatal(err)
				}
				if err := os.WriteFile(executable+".ms-build.json", data, 0600); err != nil {
					t.Fatal(err)
				}
			}
			writeMetadata()
			inspection := tooling.Inspection{Format: 1, Sources: []tooling.Source{{File: file, SHA256: digest(standard)}}}
			view, err := loadSourceView(executable, inspection)
			if err != nil {
				t.Fatalf("embedded source required a physical file: %v", err)
			}
			location := api.Location{File: filepath.Join(root, filepath.FromSlash(file)), Line: 1}
			if frame := view.frame(location, 0); !frame.Source || frame.File != file {
				t.Fatal("virtual source mapping lost", frame)
			}
			if err := os.Mkdir(filepath.Join(root, "@std"), 0700); err != nil {
				t.Fatal(err)
			}
			if err := os.WriteFile(location.File, []byte("untrusted physical shadow"), 0600); err != nil {
				t.Fatal(err)
			}
			if _, err := loadSourceView(executable, inspection); err != nil {
				t.Fatalf("physical shadow replaced pinned source: %v", err)
			}
			metadata.Sources[file] = digest([]byte("untrusted physical shadow"))
			inspection.Sources[0].SHA256 = metadata.Sources[file]
			writeMetadata()
			if _, err := loadSourceView(executable, inspection); err == nil {
				t.Fatal("accepted a standard source hash that differs from the embedded bundle")
			}
		})
	}
}
