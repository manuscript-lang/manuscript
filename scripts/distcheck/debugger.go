package main

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"

	"github.com/google/go-dap"
	"github.com/shirou/gopsutil/v4/process"
)

func systemDebugserver() (string, error) {
	candidates := []string{os.Getenv("DELVE_DEBUGSERVER_PATH"), "/Library/Developer/CommandLineTools/Library/PrivateFrameworks/LLDB.framework/Versions/A/Resources/debugserver"}
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if out, err := exec.CommandContext(ctx, "/usr/bin/xcode-select", "--print-path").Output(); err == nil {
		candidates = append(candidates, filepath.Join(strings.TrimSpace(string(out)), "..", "SharedFrameworks/LLDB.framework/Versions/A/Resources/debugserver"))
	}
	for _, name := range candidates {
		if filepath.IsAbs(name) {
			if info, err := os.Stat(name); err == nil && info.Mode().IsRegular() && info.Mode()&0111 != 0 {
				return name, nil
			}
		}
	}
	return "", fmt.Errorf("macOS native debugger check requires installed Apple debugserver from Xcode command line tools")
}

// Exercise real native debugging from the copied binary and isolated environment.
// A missing debugger, Go installation, or download fallback cannot satisfy this.
func checkDebugger(cli, directory string, environment []string, run func(string, ...string) (string, error)) error {
	source := filepath.Join(directory, "debug source.ms")
	if err := os.WriteFile(source, []byte("export fn main() -> Int:\n    let number = 41\n    let result = number + 1\n\n    return result - 42\n"), 0600); err != nil {
		return err
	}
	binary := filepath.Join(directory, "debug-program")
	if _, err := run(cli, "build", source, "--debug", "-o", binary); err != nil {
		return err
	}
	if err := checkDAP(cli, directory, environment, binary, source, true); err != nil {
		return err
	}
	// Stop while running too: EOF must halt and reap a target, not just close a
	// connection while the target remains alive. Preserve the first mapped lines.
	runningSource := filepath.Join(directory, "debug running.ms")
	if err := os.WriteFile(runningSource, []byte("export fn main() -> Int:\n    let number = 41\n    var result = number + 1\n\n    while result == 42:\n        result = result + 0\n    return result - 42\n"), 0600); err != nil {
		return err
	}
	runningBinary := binary + "-running"
	if _, err := run(cli, "build", runningSource, "--debug", "-o", runningBinary); err != nil {
		return err
	}
	if err := checkDAP(cli, directory, environment, runningBinary, runningSource, false); err != nil {
		return err
	}
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
	defer cancel()
	cmd := exec.CommandContext(ctx, cli, "debug", source)
	cmd.Dir, cmd.Env = directory, environment
	cmd.Stdin = strings.NewReader("break " + source + ":5\ncontinue\nlocals\ncontinue\nquit\n")
	output, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("standalone terminal: %w\n%s", err, output)
	}
	for _, want := range []string{"Breakpoint 1", "result = interface {}(int64) 42", "exited with status 0"} {
		if !strings.Contains(string(output), want) {
			return fmt.Errorf("standalone terminal missing %q:\n%s", want, output)
		}
	}
	return nil
}

func checkDAP(cli, directory string, environment []string, binary, source string, disconnect bool) error {
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	cmd := exec.CommandContext(ctx, cli, "dap")
	cmd.Dir, cmd.Env = directory, environment
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		return err
	}
	conn, err := cmd.StdinPipe()
	if err != nil {
		return err
	}
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	// Bound Wait even if a broken debugger leaves an inherited pipe open.
	cmd.WaitDelay = time.Second
	if err := cmd.Start(); err != nil {
		return err
	}
	waited := false
	defer func() {
		if !waited {
			_ = conn.Close()
			_ = cmd.Wait()
		}
	}()
	defer conn.Close()
	reader := bufio.NewReader(stdout)
	seq := 0
	request := func(command string, args any) error {
		seq++
		data, err := json.Marshal(map[string]any{"seq": seq, "type": "request", "command": command, "arguments": args})
		if err != nil {
			return err
		}
		return dap.WriteBaseMessage(conn, data)
	}
	pid := 0
	// Remember process events even while waiting for a response.
	receive := func(match func(dap.Message) bool) (dap.Message, error) {
		for {
			message, err := dap.ReadProtocolMessage(reader)
			if err != nil {
				return nil, err
			}
			if p, ok := message.(*dap.ProcessEvent); ok {
				pid = p.Body.SystemProcessId
			}
			if r, ok := message.(dap.ResponseMessage); ok && !r.GetResponse().Success {
				return nil, fmt.Errorf("DAP %s failed: %s", r.GetResponse().Command, r.GetResponse().Message)
			}
			if match(message) {
				return message, nil
			}
		}
	}
	response := func(command string) (dap.Message, error) {
		return receive(func(m dap.Message) bool {
			r, ok := m.(dap.ResponseMessage)
			return ok && r.GetResponse().Command == command
		})
	}
	if err := request("initialize", map[string]any{"adapterID": "manuscript", "pathFormat": "path", "linesStartAt1": true, "columnsStartAt1": true}); err != nil {
		return err
	}
	if _, err := response("initialize"); err != nil {
		return err
	}
	if err := request("launch", map[string]any{"mode": "exec", "program": binary, "outputMode": "remote"}); err != nil {
		return err
	}
	if _, err := receive(func(m dap.Message) bool { _, ok := m.(*dap.InitializedEvent); return ok }); err != nil {
		return err
	}
	if err := request("setBreakpoints", map[string]any{"source": map[string]string{"path": source}, "breakpoints": []map[string]int{{"line": 3}}}); err != nil {
		return err
	}
	reply, err := response("setBreakpoints")
	if err != nil {
		return err
	}
	bps := reply.(*dap.SetBreakpointsResponse).Body.Breakpoints
	if len(bps) != 1 || !bps[0].Verified {
		return fmt.Errorf("unverified source breakpoint: %+v", bps)
	}
	if err := request("configurationDone", map[string]any{}); err != nil {
		return err
	}
	reply, err = receive(func(m dap.Message) bool { _, ok := m.(*dap.StoppedEvent); return ok })
	if err != nil {
		return err
	}
	thread := reply.(*dap.StoppedEvent).Body.ThreadId
	if err := request("next", map[string]any{"threadId": thread}); err != nil {
		return err
	}
	if _, err := receive(func(m dap.Message) bool { _, ok := m.(*dap.StoppedEvent); return ok }); err != nil {
		return err
	}
	if err := request("stackTrace", map[string]any{"threadId": thread}); err != nil {
		return err
	}
	reply, err = response("stackTrace")
	if err != nil {
		return err
	}
	frames := reply.(*dap.StackTraceResponse).Body.StackFrames
	if len(frames) == 0 || frames[0].Source == nil || frames[0].Source.Path != source || (frames[0].Line < 4 || frames[0].Line > 5) {
		return fmt.Errorf("source step mismatch: %+v", frames)
	}
	if err := request("scopes", map[string]any{"frameId": frames[0].Id}); err != nil {
		return err
	}
	reply, err = response("scopes")
	if err != nil {
		return err
	}
	scopes := reply.(*dap.ScopesResponse).Body.Scopes
	if len(scopes) == 0 {
		return fmt.Errorf("missing locals scope")
	}
	if err := request("variables", map[string]any{"variablesReference": scopes[0].VariablesReference}); err != nil {
		return err
	}
	reply, err = response("variables")
	if err != nil {
		return err
	}
	found := false
	for _, v := range reply.(*dap.VariablesResponse).Body.Variables {
		if strings.HasSuffix(v.Name, "_result") && strings.Contains(v.Value, "42") {
			found = true
		}
	}
	if !found {
		return fmt.Errorf("missing source local result=42: %+v", reply)
	}
	if pid == 0 {
		return fmt.Errorf("missing debuggee process event")
	}
	if disconnect {
		if err := request("disconnect", map[string]any{"terminateDebuggee": true}); err != nil {
			return err
		}
		if _, err := response("disconnect"); err != nil {
			return err
		}
	} else {
		if err := request("continue", map[string]any{"threadId": thread}); err != nil {
			return err
		}
		if _, err := response("continue"); err != nil {
			return err
		}
		_ = conn.Close()
	}
	err = cmd.Wait()
	waited = true
	if err != nil {
		return fmt.Errorf("DAP shutdown (disconnect=%v): %w\n%s", disconnect, err, &stderr)
	}
	exists, err := process.PidExists(int32(pid))
	if err != nil {
		return err
	}
	if exists {
		return fmt.Errorf("debuggee %d survived DAP shutdown (disconnect=%v)", pid, disconnect)
	}
	return nil
}
