package e2e_test

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/manuscript-lang/manuscript/pkg/checker"
)

func TestExportedStandardLibraryIsValidVisibleSource(t *testing.T) {
	directory := t.TempDir()
	if output, err := commandOutput(t, cliBinary, "stdlib", directory); err != nil {
		t.Fatalf("export: %v\n%s", err, output)
	}
	files, err := filepath.Glob(filepath.Join(directory, "*.ms"))
	if err != nil || len(files) != len(checker.StandardModules()) {
		t.Fatal("missing standard modules", files, err)
	}
	var input bytes.Buffer
	frame := func(method string, id int, params any) {
		message := map[string]any{"jsonrpc": "2.0", "method": method, "params": params}
		if id != 0 {
			message["id"] = id
		}
		body, err := json.Marshal(message)
		if err != nil {
			t.Fatal(err)
		}
		fmt.Fprintf(&input, "Content-Length: %d\r\n\r\n%s", len(body), body)
	}
	frame("initialize", 1, map[string]any{})
	expectedSources := map[int]string{}
	for index, file := range files {
		source, err := os.ReadFile(file)
		if err != nil {
			t.Fatal(err)
		}
		if output, err := commandOutput(t, cliBinary, "fmt", file, "--check"); err != nil {
			t.Fatalf("user-visible %s is not valid formatted Manuscript: %v\n%s", filepath.Base(file), err, output)
		}
		uri := (&url.URL{Scheme: "file", Path: filepath.ToSlash(file)}).String()
		frame("textDocument/didOpen", 0, map[string]any{"textDocument": map[string]any{"uri": uri, "text": string(source), "version": 1}})
		id := index + 10
		expectedSources[id] = string(source)
		frame("manuscript/standardLibrarySource", id, map[string]any{"textDocument": map[string]any{"uri": "manuscript-stdlib:/" + filepath.Base(file)}})
	}
	frame("shutdown", 1000, nil)
	frame("exit", 0, nil)
	ctx, cancel := context.WithTimeout(context.Background(), time.Minute)
	defer cancel()
	command := exec.CommandContext(ctx, cliBinary, "lsp")
	command.Stdin = &input
	output, err := command.Output()
	if err != nil {
		t.Fatalf("editor session: %v\n%s", err, output)
	}
	reader := bufio.NewReader(bytes.NewReader(output))
	publications, sources := 0, 0
	for {
		length := -1
		for {
			header, err := reader.ReadString('\n')
			if err == io.EOF {
				goto complete
			}
			if err != nil {
				t.Fatal(err)
			}
			if header == "\r\n" {
				break
			}
			if strings.HasPrefix(header, "Content-Length:") {
				length, err = strconv.Atoi(strings.TrimSpace(strings.TrimPrefix(header, "Content-Length:")))
				if err != nil {
					t.Fatal(err)
				}
			}
		}
		if length < 0 {
			t.Fatal("missing response length")
		}
		body := make([]byte, length)
		if _, err := io.ReadFull(reader, body); err != nil {
			t.Fatal(err)
		}
		var message struct {
			ID     int             `json:"id"`
			Method string          `json:"method"`
			Result json.RawMessage `json:"result"`
			Error  json.RawMessage `json:"error"`
			Params struct {
				URI         string            `json:"uri"`
				Diagnostics []json.RawMessage `json:"diagnostics"`
			} `json:"params"`
		}
		if err := json.Unmarshal(body, &message); err != nil {
			t.Fatal(err)
		}
		if len(message.Error) > 0 {
			t.Fatalf("editor error: %s", body)
		}
		if message.Method == "textDocument/publishDiagnostics" {
			publications++
			if len(message.Params.Diagnostics) != 0 {
				t.Fatalf("broken visible stdlib %s: %s", message.Params.URI, body)
			}
		}
		if expected, ok := expectedSources[message.ID]; ok {
			var actual string
			if err := json.Unmarshal(message.Result, &actual); err != nil || actual != expected {
				t.Fatal("virtual stdlib differs from exported source", message.ID, err)
			}
			sources++
		}
	}
complete:
	if publications != len(files)*(len(files)+1)/2 || sources != len(files) {
		t.Fatal("incomplete stdlib editor validation", publications, sources)
	}
}
