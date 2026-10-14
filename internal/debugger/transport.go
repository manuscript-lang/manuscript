package debugger

import (
	"bufio"
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"sync"

	"github.com/google/go-dap"
)

// execTransport preserves Delve's protocol implementation while excluding its
// Go build/test launch modes and answering requests Delve cannot handle in the
// current session state. The service reports invalid modes through its normal
// DAP error response, so no second writer races outgoing event frames. Replies
// written here share one lock with outgoing frames, which Write reassembles so
// that a synthetic response never lands inside a Delve message.
type execTransport struct {
	io.ReadWriteCloser
	reader  *bufio.Reader
	pending bytes.Buffer

	mu     sync.Mutex // guards the fields below and every write to the client
	out    bytes.Buffer
	active bool // a launch or attach has produced a debug session
}

// needsSession lists requests that Delve dereferences its debugger for. Only
// the requests that create or end a session are valid before one exists.
func needsSession(command string) bool {
	switch command {
	case "", "initialize", "launch", "attach", "disconnect", "terminate":
		return false
	}
	return true
}

func (t *execTransport) Read(p []byte) (int, error) {
	for t.pending.Len() == 0 {
		data, err := dap.ReadBaseMessage(t.reader)
		if err != nil {
			return 0, err
		}
		var request struct {
			Seq       int             `json:"seq"`
			Type      string          `json:"type"`
			Command   string          `json:"command"`
			Arguments json.RawMessage `json:"arguments"`
		}
		parsed := json.Unmarshal(data, &request) == nil
		if parsed && request.Type == "request" && needsSession(request.Command) && !t.hasSession() {
			// Delve would dereference its absent debugger (pause) or answer with
			// an unrelated internal error. Say what the client must do instead.
			if err := t.reject(request.Seq, request.Command, fmt.Sprintf("no debug session: send launch or attach before %s", request.Command)); err != nil {
				return 0, err
			}
			continue
		}
		if parsed && request.Command == "launch" {
			var launch struct {
				Mode string `json:"mode"`
			}
			if json.Unmarshal(request.Arguments, &launch) == nil && launch.Mode != "exec" {
				// Replace the entire configuration before Delve applies cwd/env settings.
				// Do not permit a client to opt back into a Go build with omitted mode.
				var fields map[string]json.RawMessage
				if err := json.Unmarshal(data, &fields); err != nil {
					return 0, err
				}
				fields["arguments"] = json.RawMessage(`{"mode":"ms requires mode exec; compile with ms build --debug first"}`)
				data, err = json.Marshal(fields)
				if err != nil {
					return 0, err
				}
			}
		}
		if err := dap.WriteBaseMessage(&t.pending, data); err != nil {
			return 0, err
		}
	}
	return t.pending.Read(p)
}

func (t *execTransport) hasSession() bool {
	t.mu.Lock()
	defer t.mu.Unlock()
	return t.active
}

// reject answers a request with a protocol error response.
func (t *execTransport) reject(seq int, command, message string) error {
	response := &dap.ErrorResponse{Response: dap.Response{
		ProtocolMessage: dap.ProtocolMessage{Type: "response"},
		RequestSeq:      seq, Success: false, Command: command, Message: message,
	}}
	response.Body.Error = &dap.ErrorMessage{Format: message}
	t.mu.Lock()
	defer t.mu.Unlock()
	return dap.WriteProtocolMessage(t.ReadWriteCloser, response)
}

// Write forwards Delve's output one whole frame at a time and records the
// session state each frame implies.
func (t *execTransport) Write(p []byte) (int, error) {
	t.mu.Lock()
	defer t.mu.Unlock()
	t.out.Write(p)
	for {
		frame, ok := t.nextFrame()
		if !ok {
			return len(p), nil
		}
		t.observe(frame)
		if _, err := t.ReadWriteCloser.Write(frame); err != nil {
			return 0, err
		}
	}
}

// nextFrame removes one complete Content-Length framed message from the
// buffer, header included.
func (t *execTransport) nextFrame() ([]byte, bool) {
	buffered := t.out.Bytes()
	end := bytes.Index(buffered, []byte("\r\n\r\n"))
	if end < 0 {
		return nil, false
	}
	var length int
	if _, err := fmt.Sscanf(string(buffered[:end]), "Content-Length: %d", &length); err != nil || length < 0 {
		// Not a frame this layer understands: pass everything through unchanged.
		return append([]byte(nil), t.out.Next(len(buffered))...), true
	}
	if len(buffered) < end+4+length {
		return nil, false
	}
	return append([]byte(nil), t.out.Next(end+4+length)...), true
}

// observe tracks when Delve has a debugger. Delve announces a configurable
// session with the initialized event, and a launch or attach that succeeds
// without one (noDebug launches) with its response.
func (t *execTransport) observe(frame []byte) {
	_, body, ok := bytes.Cut(frame, []byte("\r\n\r\n"))
	if !ok {
		return
	}
	var message struct {
		Type    string `json:"type"`
		Event   string `json:"event"`
		Command string `json:"command"`
		Success bool   `json:"success"`
	}
	if json.Unmarshal(body, &message) != nil {
		return
	}
	switch {
	case message.Type == "event" && message.Event == "initialized":
		t.active = true
	case message.Type == "response" && message.Success && (message.Command == "launch" || message.Command == "attach"):
		t.active = true
	}
}
