// Package mcp serves Manuscript tooling to agents over the Model Context Protocol.
package mcp

import (
	"bufio"
	"context"
	"encoding/json"
	"errors"
	"io"
	"sync"
	"time"
)

// supportedVersions lists the protocol revisions the server speaks, newest first.
// The server answers with the client's revision when it is listed, else the newest.
var supportedVersions = []string{"2025-06-18", "2025-03-26", "2024-11-05"}

const maxMessageBytes = 8 << 20

// Server answers MCP requests on one stdio-style connection.
type Server struct {
	Version string // compiler version reported at initialization
	Exec    Executor
	out     io.Writer
	mu      sync.Mutex
}

type request struct {
	ID     json.RawMessage `json:"id,omitempty"`
	Method string          `json:"method"`
	Params json.RawMessage `json:"params,omitempty"`
}

type rpcError struct {
	Code    int    `json:"code"`
	Message string `json:"message"`
}

const (
	codeParse          = -32700
	codeInvalidRequest = -32600
	codeMethodNotFound = -32601
	codeInvalidParams  = -32602
)

// Serve reads newline-delimited JSON-RPC messages until input closes.
// Requests run one at a time, which keeps tool output ordered for the client.
func (s *Server) Serve(ctx context.Context, in io.Reader, out io.Writer) error {
	s.out = out
	reader := bufio.NewReaderSize(in, 64<<10)
	for ctx.Err() == nil {
		line, err := readLine(reader)
		if len(line) > 0 {
			s.handle(ctx, line)
		}
		if errors.Is(err, io.EOF) {
			return nil
		}
		if err != nil {
			return err
		}
	}
	return ctx.Err()
}

func readLine(reader *bufio.Reader) ([]byte, error) {
	var line []byte
	for {
		chunk, err := reader.ReadSlice('\n')
		line = append(line, chunk...)
		if len(line) > maxMessageBytes {
			return nil, errors.New("mcp message exceeds 8 MiB")
		}
		if errors.Is(err, bufio.ErrBufferFull) {
			continue
		}
		return trimSpace(line), err
	}
}

func trimSpace(b []byte) []byte {
	for len(b) > 0 && (b[len(b)-1] == '\n' || b[len(b)-1] == '\r' || b[len(b)-1] == ' ') {
		b = b[:len(b)-1]
	}
	return b
}

func (s *Server) handle(ctx context.Context, line []byte) {
	var req request
	if err := json.Unmarshal(line, &req); err != nil {
		s.reply(nil, nil, &rpcError{codeParse, "invalid JSON: " + err.Error()})
		return
	}
	notification := len(req.ID) == 0
	if req.Method == "" {
		if !notification {
			s.reply(req.ID, nil, &rpcError{codeInvalidRequest, "missing method"})
		}
		return
	}
	result, problem := s.dispatch(ctx, req)
	if notification {
		return
	}
	s.reply(req.ID, result, problem)
}

func (s *Server) reply(id json.RawMessage, result any, problem *rpcError) {
	message := map[string]any{"jsonrpc": "2.0", "id": json.RawMessage("null")}
	if len(id) > 0 {
		message["id"] = id
	}
	if problem != nil {
		message["error"] = problem
	} else {
		message["result"] = result
	}
	data, err := json.Marshal(message)
	if err != nil {
		return
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	_, _ = s.out.Write(append(data, '\n'))
}

func (s *Server) dispatch(ctx context.Context, req request) (any, *rpcError) {
	switch req.Method {
	case "initialize":
		return s.initialize(req.Params), nil
	case "ping":
		return map[string]any{}, nil
	case "tools/list":
		return map[string]any{"tools": toolDefinitions()}, nil
	case "tools/call":
		return s.callTool(ctx, req.Params)
	case "resources/list":
		return map[string]any{"resources": listResources()}, nil
	case "resources/templates/list":
		return map[string]any{"resourceTemplates": resourceTemplates()}, nil
	case "resources/read":
		return readResource(req.Params)
	case "prompts/list":
		return map[string]any{"prompts": listPrompts()}, nil
	case "prompts/get":
		return getPrompt(req.Params)
	}
	return nil, &rpcError{codeMethodNotFound, "unknown method " + req.Method}
}

func (s *Server) initialize(params json.RawMessage) any {
	var p struct {
		ProtocolVersion string `json:"protocolVersion"`
	}
	_ = json.Unmarshal(params, &p)
	version := supportedVersions[0]
	for _, candidate := range supportedVersions {
		if candidate == p.ProtocolVersion {
			version = candidate
		}
	}
	return map[string]any{
		"protocolVersion": version,
		"capabilities": map[string]any{
			"tools":     map[string]any{},
			"resources": map[string]any{},
			"prompts":   map[string]any{},
		},
		"serverInfo":   map[string]any{"name": "manuscript", "version": s.Version},
		"instructions": instructions,
	}
}

const instructions = "Write and verify .ms source. Read the manuscript_cheatsheet prompt once, search_stdlib any std API before use, check after every edit. test, run, and build take a project ms.toml only."

// progressInterval spaces progress notifications during slow tools.
var progressInterval = 5 * time.Second

// reportProgress sends notifications/progress until the returned stop function
// runs. Clients that sent no progress token get nothing.
func (s *Server) reportProgress(token json.RawMessage, tool string) (stop func()) {
	if len(token) == 0 {
		return func() {}
	}
	done := make(chan struct{})
	go func() {
		ticker := time.NewTicker(progressInterval)
		defer ticker.Stop()
		for n := 1; ; n++ {
			select {
			case <-done:
				return
			case <-ticker.C:
				s.notify("notifications/progress", map[string]any{"progressToken": token, "progress": n, "message": tool + " running"})
			}
		}
	}()
	return func() { close(done) }
}

func (s *Server) notify(method string, params any) {
	data, err := json.Marshal(map[string]any{"jsonrpc": "2.0", "method": method, "params": params})
	if err != nil {
		return
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	_, _ = s.out.Write(append(data, '\n'))
}
