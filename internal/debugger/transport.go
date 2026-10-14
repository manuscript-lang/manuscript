package debugger

import (
	"bufio"
	"bytes"
	"encoding/json"
	"io"

	"github.com/google/go-dap"
)

// execTransport preserves Delve's protocol implementation while excluding its
// Go build/test launch modes. The service reports invalid modes through its
// normal DAP error response, so no second writer races outgoing event frames.
type execTransport struct {
	io.ReadWriteCloser
	reader  *bufio.Reader
	pending bytes.Buffer
}

func (t *execTransport) Read(p []byte) (int, error) {
	if t.pending.Len() == 0 {
		data, err := dap.ReadBaseMessage(t.reader)
		if err != nil {
			return 0, err
		}
		var request struct {
			Command   string          `json:"command"`
			Arguments json.RawMessage `json:"arguments"`
		}
		if json.Unmarshal(data, &request) == nil && request.Command == "launch" {
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
