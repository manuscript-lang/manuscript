package e2e_test

import (
	"bytes"
	"encoding/json"
	"io"
	"os"
	"path/filepath"
	"reflect"
	"runtime"
	"testing"
	"time"
)

func loggingRecords(t *testing.T, data []byte) []map[string]any {
	t.Helper()
	if len(data) == 0 || data[len(data)-1] != '\n' {
		t.Fatalf("missing complete JSON lines: %q", data)
	}
	lines := bytes.Split(data[:len(data)-1], []byte{'\n'})
	records := make([]map[string]any, len(lines))
	for i, line := range lines {
		decoder := json.NewDecoder(bytes.NewReader(line))
		decoder.UseNumber()
		if err := decoder.Decode(&records[i]); err != nil || records[i] == nil {
			t.Fatalf("line %d is not a JSON object: %q (%v)", i+1, line, err)
		}
		if err := decoder.Decode(new(any)); err != io.EOF {
			t.Fatalf("extra data on line %d: %q (%v)", i+1, line, err)
		}
	}
	return records
}

func TestLoggingCLI(t *testing.T) {
	root := t.TempDir()
	t.Setenv("MANUSCRIPT_CACHE_DIR", filepath.Join(root, "cache"))
	source := "testdata/projects/logging/main.ms"
	// The CLI reads these fixtures in a subprocess. Record the inputs here so
	// edits invalidate Go's test cache even when the harness stays unchanged.
	for _, name := range []string{"main.ms", "records.ms"} {
		if _, err := os.ReadFile(filepath.Join(filepath.Dir(source), name)); err != nil {
			t.Fatal(err)
		}
	}
	want := []map[string]any{
		{"level": json.Number("30"), "msg": "received \"payload\"\nnext", "service": "worker", "request": "req-1", "count": json.Number("9007199254740993"), "ok": true, "nested": []any{nil, false}},
		{"level": json.Number("40"), "msg": "complete", "service": "api"},
	}

	t.Run("run stdout", func(t *testing.T) {
		before := time.Now().UnixMilli()
		output, err := commandOutput(t, cliBinary, "run", source, "--", "stdout")
		after := time.Now().UnixMilli()
		if err != nil {
			t.Fatalf("CLI run failed: %v\n%s", err, output)
		}
		records := loggingRecords(t, output)
		if len(records) != 3 {
			t.Fatalf("got %d records, want 3: %s", len(records), output)
		}
		for i := 0; i < 2; i++ {
			number, ok := records[i]["time"].(json.Number)
			if !ok {
				t.Fatalf("record %d has no numeric timestamp: %v", i, records[i])
			}
			timestamp, err := number.Int64()
			if err != nil || timestamp < before || timestamp > after {
				t.Fatalf("record %d timestamp %q is outside execution interval", i, number)
			}
			delete(records[i], "time")
		}
		expected := append(append([]map[string]any{}, want...), map[string]any{"level": json.Number("30"), "msg": "still open"})
		if !reflect.DeepEqual(records, expected) {
			t.Fatalf("stdout records: got %#v, want %#v", records, expected)
		}
	})

	binary := filepath.Join(root, "logging")
	if runtime.GOOS == "windows" {
		binary += ".exe"
	}
	if output, err := commandOutput(t, cliBinary, "build", source, "-o", binary); err != nil {
		t.Fatalf("CLI build failed: %v\n%s", err, output)
	}

	t.Run("file append across processes", func(t *testing.T) {
		path := filepath.Join(root, "events.ndjson")
		var first []byte
		for run := 0; run < 2; run++ {
			output, err := commandOutput(t, binary, "file", path)
			if err != nil || len(output) != 0 {
				t.Fatalf("file logging leaked output or failed: %v\n%s", err, output)
			}
			data, err := os.ReadFile(path)
			if err != nil {
				t.Fatal(err)
			}
			expected := append([]map[string]any{}, want...)
			if run == 0 {
				first = append([]byte{}, data...)
			} else {
				expected = append(expected, want...)
				if !bytes.Equal(data, append(append([]byte{}, first...), first...)) {
					t.Fatalf("second process did not append identical records: %q", data)
				}
			}
			if records := loggingRecords(t, data); !reflect.DeepEqual(records, expected) {
				t.Fatalf("file records: got %#v, want %#v", records, expected)
			}
		}
	})

	t.Run("concurrent child records", func(t *testing.T) {
		path := filepath.Join(root, "concurrent.ndjson")
		if output, err := commandOutput(t, binary, "concurrent", path); err != nil || len(output) != 0 {
			t.Fatalf("concurrent logging failed: %v\n%s", err, output)
		}
		data, err := os.ReadFile(path)
		if err != nil {
			t.Fatal(err)
		}
		records := loggingRecords(t, data)
		if len(records) != 64 {
			t.Fatalf("got %d concurrent records, want 64", len(records))
		}
		seen := map[[2]int64]bool{}
		for _, record := range records {
			worker, workerOK := record["worker"].(json.Number)
			sequence, sequenceOK := record["sequence"].(json.Number)
			if !workerOK || !sequenceOK {
				t.Fatalf("missing task identity: %#v", record)
			}
			w, wErr := worker.Int64()
			s, sErr := sequence.Int64()
			key := [2]int64{w, s}
			if wErr != nil || sErr != nil || w < 0 || w >= 8 || s < 0 || s >= 8 || seen[key] {
				t.Fatalf("invalid or duplicated task identity: %#v", record)
			}
			seen[key] = true
			if len(record) != 5 || record["level"] != json.Number("30") || record["msg"] != "concurrent" || record["service"] != "api" {
				t.Fatalf("corrupt concurrent record: %#v", record)
			}
		}
	})

	for _, test := range []struct{ mode, diagnostic string }{
		{"missing", "FileSystemError.NotFound"},
		{"invalid", "LogError.InvalidData"},
		{"limit", "LogError.LimitExceeded"},
		{"closed", "LogError.Closed"},
	} {
		t.Run("failure "+test.mode, func(t *testing.T) {
			output, err := commandOutput(t, binary, test.mode, filepath.Join(root, "missing", "events.ndjson"))
			if exit, ok := err.(interface{ ExitCode() int }); !ok || exit.ExitCode() != 1 {
				t.Fatalf("expected exit 1, got %v\n%s", err, output)
			}
			if string(output) != test.diagnostic+"\n" {
				t.Fatalf("failure emitted partial logs or lost its diagnostic: %q", output)
			}
		})
	}
}
