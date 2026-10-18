package lsp

import (
	"context"
	"errors"
	"reflect"
	"strings"
	"testing"
)

func TestCanceledDocumentPhaseDoesNotBuildIndex(t *testing.T) {
	for _, method := range []string{"semanticTokens/full", "hover", "definition", "references", "typeDefinition", "documentHighlight", "prepareRename"} {
		t.Run(method, func(t *testing.T) {
			d := performanceProject(t, 1, 2)
			if method == "typeDefinition" {
				d.Text = "type Item:\n    value: Int\n\n" + strings.ReplaceAll(strings.ReplaceAll(d.Text, "f_0_0(1)", "Item(value: 1)"), "return result", "return result.value")
			}
			s := snapshotServer(d)
			checked := s.checkedDocument(d)
			// Analysis has finished; cancellation is visible when the next
			// request-handler phase enters. Bypass the already-tested transport
			// dispatch guard to exercise this phase boundary deterministically.
			s.transport = &transport{pending: map[string]bool{"1": true}}
			r := &request{Method: "textDocument/" + method, ID: []byte("1")}
			r.params.TextDocument.URI = d.URI
			r.params.Position = Position(d.Text, strings.LastIndex(d.Text, "result"))
			s.documentRequest(r)
			if len(s.indices) != 0 || s.cache[d.URI].Program != checked.Program {
				t.Fatal("canceled phase built an index or replaced complete checked state")
			}
			s.transport.pending["1"] = false
			result, rpcError := s.documentRequest(r)
			if rpcError != nil || result == nil || len(s.indices) != 1 {
				t.Fatal("uncanceled phase lost its complete result", result, rpcError)
			}
		})
	}
}

func TestRenameCancellationAfterIndex(t *testing.T) {
	d := performanceProject(t, 1, 2)
	checked := analyze(d, map[string]document{d.URI: d})
	index := sourceIndex(checked)
	// An unresolved position is a distinguishing control: cancellation after
	// indexing must win before selection would report an ordinary rename error.
	edit, err := renameIndexed(checked, index, d, position{}, "renamed", func() bool { return true })
	if edit != nil || !errors.Is(err, context.Canceled) {
		t.Fatal("rename started selection after index-phase cancellation", edit, err)
	}
	if _, err := renameIndexed(checked, index, d, position{}, "renamed", nil); err == nil || errors.Is(err, context.Canceled) {
		t.Fatal("unresolved-position negative control did not distinguish selection", err)
	}
}

func TestRenameChangesStopsBetweenFiles(t *testing.T) {
	first := document{URI: "file:///tmp/a.ms", Text: "fn first() Int: 1\n", Version: 7}
	second := document{URI: "file:///tmp/b.ms", Text: "\"unfinished", Version: 9}
	docs := map[string]document{first.URI: first, second.URI: second}
	byURI := map[string][]renameReplacement{
		first.URI: {{3, 8, "changed"}}, second.URI: {{0, 1, "changed"}},
	}
	calls := 0
	modified, edits, err := renameChanges(docs, docs, byURI, "changed", func() bool { calls++; return calls == 2 })
	if !errors.Is(err, context.Canceled) || modified != nil || edits != nil || calls != 2 {
		t.Fatal("rename continued to the second file or returned partial edits", modified, edits, err, calls)
	}
	if docs[first.URI] != first || docs[second.URI] != second {
		t.Fatal("canceled rename mutated live documents")
	}
	if _, _, err := renameChanges(docs, docs, byURI, "changed", nil); err == nil || errors.Is(err, context.Canceled) {
		t.Fatal("second-file lexical negative control did not execute", err)
	}
	docs[second.URI] = document{URI: second.URI, Text: "fn other() Int: 2\n", Version: 9}
	byURI[second.URI] = []renameReplacement{{3, 8, "changed"}}
	modified, edits, err = renameChanges(docs, docs, byURI, "changed", nil)
	if err != nil || len(edits) != 2 || modified[first.URI].Text != "fn changed() Int: 1\n" || modified[second.URI].Text != "fn changed() Int: 2\n" {
		t.Fatal("uncanceled rename lost full edits", modified, edits, err)
	}
	if !reflect.DeepEqual(edits[0].(map[string]any)["textDocument"], map[string]any{"uri": first.URI, "version": 7}) {
		t.Fatal("rename lost original document version", edits)
	}
}

func TestWorkspaceCancellationStopsDiscoveryScopes(t *testing.T) {
	d := performanceProject(t, 1, 2)
	docs := map[string]document{d.URI: d, "file:///tmp/other/a.ms": {URI: "file:///tmp/other/a.ms"}}
	for _, cancelAt := range []int{1, 3} {
		calls := 0
		got := workspaceSymbolsWithCancel(docs, []string{"/tmp/additional-root"}, "f_", func() bool { calls++; return calls >= cancelAt })
		if got != nil || calls != cancelAt {
			t.Fatal("canceled discovery continued into additional roots", got, calls, cancelAt)
		}
	}
}
