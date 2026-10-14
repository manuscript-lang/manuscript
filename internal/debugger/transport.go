package debugger

import (
	"bufio"
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"regexp"
	"strconv"
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
	// startSession runs before each launch or attach reaches Delve.
	startSession func()

	mu     sync.Mutex // guards the fields below and every write to the client
	out    bytes.Buffer
	active bool // a launch or attach has produced a debug session
	exited bool // the target finished; resuming requests cannot succeed
	// status is the exit status Delve printed for a finished target.
	status *int
	// terminates holds terminate requests answered by a disconnect.
	terminates map[int]bool
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

// resumes lists requests that cannot succeed once the target has finished.
func resumes(command string) bool {
	switch command {
	case "continue", "next", "stepIn", "stepOut", "stepBack", "reverseContinue", "pause":
		return true
	}
	return false
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
		if parsed && (request.Command == "launch" || request.Command == "attach") && t.startSession != nil {
			t.startSession()
		}
		if parsed && request.Type == "request" && needsSession(request.Command) && !t.hasSession() {
			// Delve would dereference its absent debugger (pause) or answer with
			// an unrelated internal error. Say what the client must do instead.
			if err := t.reject(request.Seq, request.Command, fmt.Sprintf("no debug session: send launch or attach before %s", request.Command)); err != nil {
				return 0, err
			}
			continue
		}
		if parsed && request.Type == "request" && resumes(request.Command) && t.hasExited() {
			// Delve would resume a finished target and report the failure as a
			// stopped event with reason error after a successful response.
			if err := t.reject(request.Seq, request.Command, fmt.Sprintf("the debuggee has exited: %s has nothing to resume", request.Command)); err != nil {
				return 0, err
			}
			continue
		}
		if parsed && request.Type == "request" && request.Command == "terminate" {
			// Delve answers terminate with "Not yet implemented". Ending the
			// session and the target is what disconnect with terminateDebuggee
			// does, also when no target is running; the response keeps the
			// command that was asked for.
			t.markTerminate(request.Seq)
			fields := map[string]json.RawMessage{}
			if err := json.Unmarshal(data, &fields); err != nil {
				return 0, err
			}
			fields["command"] = json.RawMessage(`"disconnect"`)
			fields["arguments"] = json.RawMessage(`{"terminateDebuggee":true}`)
			if data, err = json.Marshal(fields); err != nil {
				return 0, err
			}
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

func (t *execTransport) hasExited() bool {
	t.mu.Lock()
	defer t.mu.Unlock()
	return t.exited
}

func (t *execTransport) markTerminate(seq int) {
	t.mu.Lock()
	defer t.mu.Unlock()
	if t.terminates == nil {
		t.terminates = map[int]bool{}
	}
	t.terminates[seq] = true
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
		for _, out := range t.observe(frame) {
			if _, err := t.ReadWriteCloser.Write(out); err != nil {
				return 0, err
			}
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

var exitStatus = regexp.MustCompile(`has exited with status (-?\d+)`)

// observe tracks the session state a frame from Delve implies and returns the
// frames to forward. Delve announces a configurable session with the
// initialized event, and a launch or attach that succeeds without one (noDebug
// launches) with its response. It ends a target with terminated alone; when it
// has printed the exit status, exited is reported first as the protocol
// describes. An exit code the adapter does not have is never invented.
func (t *execTransport) observe(frame []byte) [][]byte {
	_, body, ok := bytes.Cut(frame, []byte("\r\n\r\n"))
	if !ok {
		return [][]byte{frame}
	}
	var message struct {
		Type       string `json:"type"`
		Event      string `json:"event"`
		Command    string `json:"command"`
		Success    bool   `json:"success"`
		RequestSeq int    `json:"request_seq"`
		Body       struct {
			Output string `json:"output"`
		} `json:"body"`
	}
	if json.Unmarshal(body, &message) != nil {
		return [][]byte{frame}
	}
	switch {
	case message.Type == "event" && message.Event == "initialized":
		t.active = true
	case message.Type == "event" && message.Event == "output":
		if m := exitStatus.FindStringSubmatch(message.Body.Output); m != nil {
			if status, err := strconv.Atoi(m[1]); err == nil {
				t.status = &status
			}
		}
	case message.Type == "event" && message.Event == "terminated":
		first := !t.exited
		t.exited = true
		if first && t.status != nil {
			return [][]byte{exitedEvent(*t.status), frame}
		}
	case message.Type == "response" && message.Success && (message.Command == "launch" || message.Command == "attach"):
		t.active = true
	case message.Type == "response" && message.Success && message.Command == "restart":
		t.exited, t.status = false, nil
	case message.Type == "response" && message.Command == "disconnect" && t.terminates[message.RequestSeq]:
		delete(t.terminates, message.RequestSeq)
		fields := map[string]json.RawMessage{}
		if json.Unmarshal(body, &fields) != nil {
			break
		}
		fields["command"] = json.RawMessage(`"terminate"`)
		data, err := json.Marshal(fields)
		if err != nil {
			break
		}
		var framed bytes.Buffer
		if dap.WriteBaseMessage(&framed, data) == nil {
			return [][]byte{framed.Bytes()}
		}
	}
	return [][]byte{frame}
}

func exitedEvent(status int) []byte {
	event := &dap.ExitedEvent{Event: dap.Event{ProtocolMessage: dap.ProtocolMessage{Type: "event"}, Event: "exited"}}
	event.Body.ExitCode = status
	var framed bytes.Buffer
	if dap.WriteProtocolMessage(&framed, event) != nil {
		return nil
	}
	return framed.Bytes()
}
