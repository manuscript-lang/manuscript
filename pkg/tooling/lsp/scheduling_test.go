package lsp

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func queuedMessage(t testing.TB, method string, id any, params any) incoming {
	t.Helper()
	body, err := readFrame(bufio.NewReader(strings.NewReader(frame(method, id, params))))
	if err != nil {
		t.Fatal(err)
	}
	return incoming{body: body, change: method == "textDocument/didChange" && id == nil}
}

func readMessages(t testing.TB, output *bytes.Buffer) []map[string]any {
	t.Helper()
	reader := bufio.NewReader(output)
	var messages []map[string]any
	for {
		body, err := readFrame(reader)
		if err == io.EOF {
			return messages
		}
		if err != nil {
			t.Fatal(err)
		}
		var message map[string]any
		if err := json.Unmarshal(body, &message); err != nil {
			t.Fatal(err)
		}
		messages = append(messages, message)
	}
}

func TestQueuedChangesPreserveRangesVersionsAndErrors(t *testing.T) {
	d := document{"file:///tmp/queued.ms", "# 😀\r\nfn answer() Int:\r\n    return 1\r\n", 1}
	s := snapshotServer(d)
	var output bytes.Buffer
	s.output = &output
	s.transport = &transport{messages: make(chan incoming, 16), pending: map[string]bool{}}
	change := func(version int, changes ...any) {
		s.transport.messages <- queuedMessage(t, "textDocument/didChange", nil, map[string]any{
			"textDocument": document{URI: d.URI, Version: version}, "contentChanges": changes,
		})
	}
	change(2, map[string]any{"range": span{position{0, 2}, position{0, 4}}, "text": "alpha"})
	// This range is valid only after the preceding surrogate-pair replacement.
	change(3, map[string]any{"range": span{position{0, 7}, position{0, 7}}, "text": " beta"})
	change(4, map[string]any{"range": span{position{2, 11}, position{2, 12}}, "text": "missing"})
	s.transport.messages <- queuedMessage(t, "textDocument/documentSymbol", 7, map[string]any{"textDocument": document{URI: d.URI}})
	valid := "# alpha beta\r\nfn answer() Int:\r\n    return 2\r\n"
	change(5, map[string]any{"text": valid})
	change(4, map[string]any{"text": "invalid stale source!"})
	close(s.transport.messages)
	if err := s.serveMessages(); err != nil {
		t.Fatal(err)
	}
	if got := s.docs[d.URI]; got.Version != 5 || got.Text != valid {
		t.Fatalf("ordered edits or stale guard lost: %+v", got)
	}
	messages := readMessages(t, &output)
	if len(messages) != 3 || messages[1]["id"] != float64(7) {
		t.Fatal("expected diagnostics, request barrier, EOF diagnostics", messages)
	}
	broken := messages[0]["params"].(map[string]any)
	restored := messages[2]["params"].(map[string]any)
	if broken["version"] != float64(4) || len(broken["diagnostics"].([]any)) == 0 || restored["version"] != float64(5) || len(restored["diagnostics"].([]any)) != 0 {
		t.Fatal("latest errors suppressed or restoration lost", messages)
	}
	if !strings.Contains(fmt.Sprint(messages[1]["result"]), "answer") {
		t.Fatal("request barrier lost source declarations", messages[1])
	}
}

func TestQueuedChangesHaveBoundedBatchesAndCloseBarrier(t *testing.T) {
	d := document{"file:///tmp/bounded.ms", "fn answer() Int: 1\n", 1}
	s := snapshotServer(d)
	var output bytes.Buffer
	s.output = &output
	// Larger test queue deterministically exercises the production 32-change
	// batch limit; the real transport remains bounded at 32 queued frames.
	s.transport = &transport{messages: make(chan incoming, 80), pending: map[string]bool{}}
	for version := 2; version <= 66; version++ {
		s.transport.messages <- queuedMessage(t, "textDocument/didChange", nil, map[string]any{
			"textDocument":   document{URI: d.URI, Version: version},
			"contentChanges": []any{map[string]any{"text": fmt.Sprintf("fn answer() Int: %d\n", version)}},
		})
	}
	s.transport.messages <- queuedMessage(t, "textDocument/didClose", nil, map[string]any{"textDocument": document{URI: d.URI}})
	close(s.transport.messages)
	if err := s.serveMessages(); err != nil {
		t.Fatal(err)
	}
	messages := readMessages(t, &output)
	if len(messages) < 4 || len(messages) > 66 {
		t.Fatal("changes were not bounded/coalesced", len(messages))
	}
	last := messages[len(messages)-2]["params"].(map[string]any)
	cleared := messages[len(messages)-1]["params"].(map[string]any)
	if last["version"] != float64(66) || len(cleared["diagnostics"].([]any)) != 0 || len(s.docs) != 0 || len(s.cache) != 0 || len(s.indices) != 0 {
		t.Fatal("close failed to flush latest state and release caches", messages)
	}
}

func TestTransportBurstPublishesLatestInvalidVersion(t *testing.T) {
	uri := "file:///tmp/transport-burst.ms"
	var input strings.Builder
	input.WriteString(frame("textDocument/didOpen", nil, map[string]any{"textDocument": document{uri, "fn answer() Int: 1\n", 1}}))
	for version := 2; version <= 101; version++ {
		source := "fn answer() Int: 2\n"
		if version == 101 {
			source = "fn answer() Int: missing\n"
		}
		input.WriteString(frame("textDocument/didChange", nil, map[string]any{
			"textDocument": document{URI: uri, Version: version}, "contentChanges": []any{map[string]any{"text": source}},
		}))
	}
	input.WriteString(frame("shutdown", 9, nil) + frame("exit", nil, nil))
	var output bytes.Buffer
	if err := Serve(strings.NewReader(input.String()), &output); err != nil {
		t.Fatal(err)
	}
	var latest map[string]any
	for _, message := range readMessages(t, &output) {
		if message["method"] == "textDocument/publishDiagnostics" {
			latest = message["params"].(map[string]any)
		}
	}
	if latest == nil || latest["version"] != float64(101) || len(latest["diagnostics"].([]any)) == 0 {
		t.Fatal("bounded transport lost newest errors before shutdown", latest)
	}
}

func TestCanceledRequestSkipsAnalysisAndReleasesPendingID(t *testing.T) {
	d := document{"file:///tmp/canceled.ms", "fn answer() Int: 1\n", 1}
	s := snapshotServer(d)
	var output bytes.Buffer
	s.output = &output
	s.transport = &transport{pending: map[string]bool{"7": true}}
	message := queuedMessage(t, "textDocument/hover", 7, map[string]any{"textDocument": document{URI: d.URI}, "position": position{0, 4}})
	if err := s.serve(message.body); err != nil {
		t.Fatal(err)
	}
	if len(s.cache) != 0 || len(s.analyses) != 0 || len(s.indices) != 0 || len(s.transport.pending) != 0 {
		t.Fatal("canceled queued request performed analysis or retained ID")
	}
	messages := readMessages(t, &output)
	if len(messages) != 1 || messages[0]["error"].(map[string]any)["code"] != float64(-32800) {
		t.Fatal(messages)
	}
}

func TestWorkspaceCancellationPreservesCompleteUncanceledResults(t *testing.T) {
	d := performanceProject(t, 4, 3)
	docs := map[string]document{d.URI: d}
	all := workspaceSymbolsWithCancel(docs, nil, "f_", nil)
	if len(all) != 12 {
		t.Fatal("uncanceled workspace symbols lost declarations", len(all))
	}
	calls := 0
	canceled := func() bool { calls++; return calls >= 6 }
	if got := workspaceSymbolsWithCancel(docs, nil, "f_", canceled); len(got) != 0 || calls > 20 {
		t.Fatal("workspace scan ignored cancellation", len(got), calls)
	}
	checked := analyze(d, docs)
	index := sourceIndex(checked)
	use := Position(d.Text, strings.LastIndex(d.Text, "f_0_0"))
	refs := workspaceReferencesChecked(checked, index, d, docs, use, true, nil)
	if len(refs) != 3 {
		t.Fatal("uncanceled references lost declaration/import/call", refs)
	}
	if got := workspaceReferencesChecked(checked, index, d, docs, use, true, func() bool { return true }); len(got) != 0 {
		t.Fatal("canceled references returned partial edits", got)
	}
	if edit, err := renameWithCancel(checked, d, use, "changed", func() bool { return true }, docs); edit != nil || err == nil {
		t.Fatal("canceled rename proposed an edit", edit, err)
	}
}

func TestUnrelatedWatchPreservesGenerationAndRelevantWatchInvalidates(t *testing.T) {
	d := performanceProject(t, 1, 2)
	s := snapshotServer(d)
	before := s.checkedDocument(d)
	watch := func(uri string) {
		params, err := json.Marshal(map[string]any{"changes": []any{map[string]any{"uri": uri, "type": 2}}})
		if err != nil {
			t.Fatal(err)
		}
		if _, _, err := s.handle(&request{Method: "workspace/didChangeWatchedFiles", Params: params}); err != nil {
			t.Fatal(err)
		}
	}
	watch(d.URI + ".unrelated.toml")
	if s.checkedDocument(d).Program != before.Program {
		t.Fatal("unrelated TOML discarded live analysis")
	}
	watch(d.URI)
	if s.checkedDocument(d).Program == before.Program {
		t.Fatal("source watch retained stale generation")
	}
}

func TestRenameCancellationAfterBeforeCheck(t *testing.T) {
	d := performanceProject(t, 1, 1)
	docs := map[string]document{d.URI: d}
	checked := analyze(d, docs)
	if !checked.Success() {
		t.Fatal(checked.Diagnostics)
	}
	// Enter validation with one target. The first checkpoint precedes its
	// strict "before" check. Make that check fail on
	// disk, then cancel: the post-check checkpoint must win over its error and
	// prevent starting the proposed-source check.
	calls := 0
	canceled := func() bool {
		calls++
		if calls == 1 {
			path := filepath.Join(filepath.Dir(filename(d.URI)), "part_0.ms")
			if err := os.WriteFile(path, []byte("invalid source!\n"), 0600); err != nil {
				t.Fatal(err)
			}
		}
		return calls >= 2
	}
	err := validateRename([]document{d}, docs, docs, canceled)
	if !errors.Is(err, context.Canceled) || calls != 2 {
		t.Fatal("rename did not observe cancellation immediately after checking", err, calls)
	}
}
