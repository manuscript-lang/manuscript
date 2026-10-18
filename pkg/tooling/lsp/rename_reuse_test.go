package lsp

import (
	"reflect"
	"strings"
	"testing"
)

func TestPrepareRenameReusesLiveIndex(t *testing.T) {
	d := performanceProject(t, 1, 2)
	s := snapshotServer(d)
	checked := s.checkedDocument(d)
	index := s.documentIndex(checked)
	r := &request{Method: "textDocument/prepareRename"}
	r.params.TextDocument.URI = d.URI
	r.params.Position = Position(d.Text, strings.LastIndex(d.Text, "result"))
	want, err := rename(checked, d, r.params.Position, "", s.docs)
	if err != nil {
		t.Fatal(err)
	}
	indexAllocs := testing.AllocsPerRun(3, func() { _ = sourceIndex(checked) })
	renameAllocs := testing.AllocsPerRun(3, func() {
		got, rpcError := s.documentRequest(r)
		if rpcError != nil || !reflect.DeepEqual(got, want) {
			t.Fatal("cached prepareRename changed its resolved range", got, rpcError, want)
		}
	})
	// Relative allocation control: preparing a local binding must not allocate
	// another whole project/standard occurrence index. No timing threshold.
	if indexAllocs == 0 || renameAllocs >= indexAllocs/4 {
		t.Fatalf("prepareRename rebuilt index-sized work: prepare=%g index=%g allocations", renameAllocs, indexAllocs)
	}
	if &s.documentIndex(checked)[0] != &index[0] {
		t.Fatal("prepareRename replaced the live checked index")
	}
}

func BenchmarkPrepareRenameLiveIndex(b *testing.B) {
	d := performanceProject(b, 40, 20)
	s := snapshotServer(d)
	s.documentIndex(s.checkedDocument(d))
	r := &request{Method: "textDocument/prepareRename"}
	r.params.TextDocument.URI = d.URI
	r.params.Position = Position(d.Text, strings.LastIndex(d.Text, "result"))
	b.ReportAllocs()
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		result, err := s.documentRequest(r)
		if err != nil || result == nil {
			b.Fatal(result, err)
		}
	}
}
