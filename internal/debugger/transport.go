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
	"time"

	"github.com/google/go-dap"
)

// execTransport preserves Delve's protocol implementation while excluding its
// Go build/test launch modes and completing the session lifecycle Delve leaves
// out: it answers requests Delve cannot handle in the current state, and it
// reports a finished target with an exited event before terminated. The
// service reports invalid modes through its normal DAP error response, so no
// second writer races outgoing event frames. Replies written here share one
// lock with outgoing frames, which Write reassembles so that a synthetic
// message never lands inside a Delve message.
type execTransport struct {
	io.ReadWriteCloser
	frames  chan clientFrame // requests from the client, read ahead of Delve
	inject  chan []byte      // requests the transport itself sends to Delve
	closed  chan struct{}
	close   sync.Once
	pending bytes.Buffer // request bytes ready for Delve's reader

	mu            sync.Mutex // guards the fields below and every write to the client
	out           bytes.Buffer
	active        bool // a launch or attach has produced a debug session
	noDebug       bool // the target runs without a debugger attached
	exited        bool // the target finished; execution requests cannot succeed
	disconnecting bool
	status        *int         // exit status reported in Delve's console output
	terminateSeqs map[int]bool // terminate requests answered by a disconnect
	probeLive     bool         // the status probe has been sent and has not answered
	held          []byte       // the terminated event delayed until the probe ends
	probeTimer    *time.Timer
}

type clientFrame struct {
	data []byte
	err  error
}

// probeSeq identifies the internal request that learns the exit status. No
// client sequence number reaches it.
const probeSeq = 1 << 30

// probeWait bounds how long a terminated event is held for the exit status.
const probeWait = 2 * time.Second

func newExecTransport(rw io.ReadWriteCloser) *execTransport {
	t := &execTransport{
		ReadWriteCloser: rw,
		frames:          make(chan clientFrame),
		inject:          make(chan []byte, 1),
		closed:          make(chan struct{}),
		terminateSeqs:   map[int]bool{},
	}
	go t.pump(bufio.NewReader(rw))
	return t
}

// pump reads client frames independently of Delve's request loop so the
// transport can also feed that loop its own requests.
func (t *execTransport) pump(reader *bufio.Reader) {
	for {
		data, err := dap.ReadBaseMessage(reader)
		select {
		case t.frames <- clientFrame{data, err}:
		case <-t.closed:
			return
		}
		if err != nil {
			return
		}
	}
}

func (t *execTransport) Close() error {
	t.close.Do(func() { close(t.closed) })
	return t.ReadWriteCloser.Close()
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
		var data []byte
		select {
		case frame := <-t.frames:
			if frame.err != nil {
				return 0, frame.err
			}
			data = frame.data
		case data = <-t.inject:
		case <-t.closed:
			return 0, io.EOF
		}
		data, err := t.screen(data)
		if err != nil {
			return 0, err
		}
		if data == nil {
			continue
		}
		if err := dap.WriteBaseMessage(&t.pending, data); err != nil {
			return 0, err
		}
	}
	return t.pending.Read(p)
}

// screen decides what Delve sees of one client message: the message itself,
// a rewritten message, or nothing when the transport has already answered.
func (t *execTransport) screen(data []byte) ([]byte, error) {
	println("IN", string(data))
	var request struct {
		Seq       int             `json:"seq"`
		Type      string          `json:"type"`
		Command   string          `json:"command"`
		Arguments json.RawMessage `json:"arguments"`
	}
	if json.Unmarshal(data, &request) != nil || request.Type != "request" {
		return data, nil
	}
	t.mu.Lock()
	active, exited := t.active, t.exited
	t.mu.Unlock()
	switch {
	case needsSession(request.Command) && !active:
		// Delve would dereference its absent debugger (pause) or answer with
		// an unrelated internal error. Say what the client must do instead.
		return nil, t.reject(request.Seq, request.Command, fmt.Sprintf("no debug session: send launch or attach before %s", request.Command))
	case resumes(request.Command) && exited:
		// Delve reports a step after exit as a stopped event with reason error.
		return nil, t.reject(request.Seq, request.Command, fmt.Sprintf("the debuggee has exited: %s has nothing to resume", request.Command))
	case request.Command == "disconnect":
		t.mu.Lock()
		t.disconnecting = true
		t.mu.Unlock()
	case request.Command == "terminate":
		// Delve does not implement terminate. It ends the session and stops the
		// target exactly as disconnect with terminateDebuggee does, including
		// when no target is running; the response keeps the command asked for.
		t.mu.Lock()
		t.disconnecting = true
		t.terminateSeqs[request.Seq] = true
		t.mu.Unlock()
		return rewrite(data, "disconnect", json.RawMessage(`{"terminateDebuggee":true}`))
	case request.Command == "launch":
		var launch struct {
			Mode    string `json:"mode"`
			NoDebug bool   `json:"noDebug"`
		}
		if json.Unmarshal(request.Arguments, &launch) != nil {
			return data, nil
		}
		if launch.Mode != "exec" {
			// Replace the entire configuration before Delve applies cwd/env settings.
			// Do not permit a client to opt back into a Go build with omitted mode.
			return rewrite(data, "launch", json.RawMessage(`{"mode":"ms requires mode exec; compile with ms build --debug first"}`))
		}
		t.mu.Lock()
		t.noDebug = launch.NoDebug
		t.mu.Unlock()
	}
	return data, nil
}

// rewrite replaces a request's command and arguments, keeping its sequence.
func rewrite(data []byte, command string, arguments json.RawMessage) ([]byte, error) {
	var fields map[string]json.RawMessage
	if err := json.Unmarshal(data, &fields); err != nil {
		return nil, err
	}
	name, _ := json.Marshal(command)
	fields["command"], fields["arguments"] = name, arguments
	return json.Marshal(fields)
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

// Write forwards Delve's output one whole frame at a time, tracks the session
// state each frame implies, and adds or withholds the messages the lifecycle
// needs.
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

// observe returns the frames to forward for one frame from Delve.
func (t *execTransport) observe(frame []byte) [][]byte {
	println("OUT", string(frame))
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
			Text   string `json:"text"`
			Reason string `json:"reason"`
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
		return t.terminated(frame)
	case message.Type == "event" && (message.Event == "continued" || message.Event == "stopped") && t.probeLive:
		// The probe's own step events are not the client's to see.
		if message.Event == "stopped" {
			if m := exitStatus.FindStringSubmatch(message.Body.Text); m != nil {
				if status, err := strconv.Atoi(m[1]); err == nil {
					t.status = &status
				}
			}
			t.probeLive = false
			return t.finishProbe()
		}
		return nil
	case message.Type == "response" && message.RequestSeq == probeSeq:
		if !message.Success {
			t.probeLive = false
			return t.finishProbe()
		}
		return nil
	case message.Type == "response" && message.Success && (message.Command == "launch" || message.Command == "attach"):
		t.active = true
	case message.Type == "response" && message.Success && message.Command == "restart":
		t.exited, t.status = false, nil
	case message.Type == "response" && message.Command == "disconnect" && t.terminateSeqs[message.RequestSeq]:
		delete(t.terminateSeqs, message.RequestSeq)
		var fields map[string]json.RawMessage
		if json.Unmarshal(body, &fields) != nil {
			break
		}
		fields["command"] = json.RawMessage(`"terminate"`)
		if data, err := json.Marshal(fields); err == nil {
			var framed bytes.Buffer
			if dap.WriteBaseMessage(&framed, data) == nil {
				return [][]byte{framed.Bytes()}
			}
		}
	}
	return [][]byte{frame}
}

// terminated handles Delve's terminated event. A target that ran to its end is
// reported with exited first, as the protocol describes; Delve sends only
// terminated and keeps the status to itself, so it is learned by asking for a
// step, which fails with the status.
func (t *execTransport) terminated(frame []byte) [][]byte {
	first := !t.exited
	t.exited = true
	if !first || t.disconnecting {
		if t.held != nil {
			// A disconnect ended the session while the event was held: this
			// terminated replaces it instead of following it.
			out := t.finishProbe()
			out[len(out)-1] = frame
			return out
		}
		return [][]byte{frame}
	}
	if t.status != nil {
		return [][]byte{exitedEvent(*t.status), frame}
	}
	if !t.active || t.noDebug {
		return [][]byte{frame}
	}
	select {
	case t.inject <- probeRequest():
	default:
		return [][]byte{frame}
	}
	t.probeLive, t.held = true, frame
	t.probeTimer = time.AfterFunc(probeWait, t.probeTimedOut)
	return nil
}

// finishProbe releases the held terminated event, preceded by exited when the
// status is known. A probe that did not learn the status reports only
// terminated, since an exit code the adapter does not have must not be invented.
func (t *execTransport) finishProbe() [][]byte {
	if t.held == nil {
		return nil
	}
	if t.probeTimer != nil {
		t.probeTimer.Stop()
	}
	held := t.held
	t.held = nil
	if t.status != nil {
		return [][]byte{exitedEvent(*t.status), held}
	}
	return [][]byte{held}
}

func (t *execTransport) probeTimedOut() {
	t.mu.Lock()
	defer t.mu.Unlock()
	for _, out := range t.finishProbe() {
		if _, err := t.ReadWriteCloser.Write(out); err != nil {
			return
		}
	}
}

func probeRequest() []byte {
	data, _ := json.Marshal(map[string]any{"seq": probeSeq, "type": "request", "command": "next", "arguments": map[string]int{"threadId": 1}})
	return data
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
