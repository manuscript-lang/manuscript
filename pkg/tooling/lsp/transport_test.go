package lsp

import (
	"bufio"
	"bytes"
	"io"
	"strings"
	"testing"
)

func TestTransportReadsCancellationWhileRequestIsPending(t *testing.T) {
	input := frame("textDocument/completion", 1, map[string]any{}) + frame("$/cancelRequest", nil, map[string]any{"id": 1})
	transport := newTransport(strings.NewReader(input))
	defer transport.close()
	first := <-transport.messages
	if first.err != nil {
		t.Fatal(first.err)
	}
	last := <-transport.messages
	if last.err != io.EOF {
		t.Fatal(last)
	}
	if !transport.canceled([]byte("1")) {
		t.Fatal("cancellation did not bypass request queue")
	}
	transport.done([]byte("1"))
	if transport.canceled([]byte("1")) {
		t.Fatal("completed request leaked")
	}
}
func TestProtocolErrorsDoNotTerminateSession(t *testing.T) {
	input := "Content-Length: 1\r\n\r\n{" + frame("textDocument/completion", 1, "invalid params") + frame("shutdown", 2, nil) + frame("exit", nil, nil)
	var output bytes.Buffer
	if err := Serve(strings.NewReader(input), &output); err != nil {
		t.Fatal(err)
	}
	for _, code := range []string{"-32700", "-32602", "\"id\":2"} {
		if !strings.Contains(output.String(), code) {
			t.Fatal(output.String())
		}
	}
}
func TestFrameLimits(t *testing.T) {
	for _, header := range []string{"Content-Length: 1\r\nContent-Length: 1\r\n\r\n{}", strings.Repeat("x", 9000) + "\n\n", "Content-Length: 2\r\n"} {
		if _, err := readFrame(bufio.NewReaderSize(strings.NewReader(header), 8192)); err == nil {
			t.Fatal("accepted malformed header")
		}
	}
}
