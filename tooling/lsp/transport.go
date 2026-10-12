package lsp

import (
	"bufio"
	"encoding/json"
	"fmt"
	"io"
	"strconv"
	"strings"
	"sync"
)

type incoming struct {
	body []byte
	err  error
}
type transport struct {
	messages chan incoming
	stop     chan struct{}
	input    io.Reader
	mutex    sync.Mutex
	pending  map[string]bool
}

func newTransport(input io.Reader) *transport {
	t := &transport{messages: make(chan incoming, 32), stop: make(chan struct{}), input: input, pending: map[string]bool{}}
	go func() {
		defer close(t.messages)
		reader := bufio.NewReaderSize(input, 8192)
		for {
			body, err := readFrame(reader)
			if err != nil {
				select {
				case t.messages <- incoming{err: err}:
				case <-t.stop:
				}
				return
			}
			var msg struct {
				ID     json.RawMessage `json:"id"`
				Method string          `json:"method"`
				Params struct {
					ID json.RawMessage `json:"id"`
				} `json:"params"`
			}
			if json.Unmarshal(body, &msg) == nil {
				if msg.Method == "$/cancelRequest" {
					t.mutex.Lock()
					if _, ok := t.pending[string(msg.Params.ID)]; ok {
						t.pending[string(msg.Params.ID)] = true
					}
					t.mutex.Unlock()
					continue
				}
				if len(msg.ID) > 0 {
					t.mutex.Lock()
					t.pending[string(msg.ID)] = false
					t.mutex.Unlock()
				}
			}
			select {
			case t.messages <- incoming{body: body}:
			case <-t.stop:
				return
			}
		}
	}()
	return t
}
func (t *transport) canceled(id json.RawMessage) bool {
	t.mutex.Lock()
	defer t.mutex.Unlock()
	return t.pending[string(id)]
}
func (t *transport) done(id json.RawMessage) {
	t.mutex.Lock()
	delete(t.pending, string(id))
	t.mutex.Unlock()
}
func (t *transport) close() {
	close(t.stop)
	if closer, ok := t.input.(io.Closer); ok {
		_ = closer.Close()
	}
}
func readFrame(reader *bufio.Reader) ([]byte, error) {
	length := -1
	headerSize := 0
	for {
		line, err := reader.ReadSlice('\n')
		headerSize += len(line)
		if headerSize > 8192 {
			return nil, fmt.Errorf("protocol header exceeds 8192 bytes")
		}
		if err == io.EOF && length == -1 && headerSize == 0 {
			return nil, io.EOF
		}
		if err != nil {
			if err == io.EOF {
				err = io.ErrUnexpectedEOF
			}
			return nil, err
		}
		trimmed := strings.TrimSpace(string(line))
		if trimmed == "" {
			break
		}
		key, value, ok := strings.Cut(trimmed, ":")
		if !ok {
			return nil, fmt.Errorf("malformed protocol header")
		}
		if strings.EqualFold(key, "Content-Length") {
			if length != -1 {
				return nil, fmt.Errorf("duplicate Content-Length")
			}
			length, err = strconv.Atoi(strings.TrimSpace(value))
			if err != nil {
				return nil, err
			}
		}
	}
	if length < 0 || length > 16<<20 {
		return nil, fmt.Errorf("invalid Content-Length")
	}
	body := make([]byte, length)
	_, err := io.ReadFull(reader, body)
	return body, err
}
