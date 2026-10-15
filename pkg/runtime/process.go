package msruntime

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"github.com/manuscript-lang/manuscript/internal/hostos"
	"os"
	"os/exec"
	"sort"
	"strings"
	"sync"
	"syscall"
	"time"
)

func sortStrings(values []string) { sort.Strings(values) }
func fmtFault(value any) string   { return fmt.Sprint(value) }

type commands struct{}
type boundedOutput struct {
	mu             sync.Mutex
	remaining      int64
	stdout, stderr bytes.Buffer
	overflow       bool
	cancel         context.CancelFunc
}
type commandOutputWriter struct {
	output *boundedOutput
	stderr bool
}

func (w commandOutputWriter) Write(data []byte) (int, error) {
	output := w.output
	output.mu.Lock()
	defer output.mu.Unlock()
	accepted := len(data)
	if int64(accepted) > output.remaining {
		accepted = int(output.remaining)
		output.overflow = true
		output.cancel()
	}
	if w.stderr {
		output.stderr.Write(data[:accepted])
	} else {
		output.stdout.Write(data[:accepted])
	}
	output.remaining -= int64(accepted)
	if accepted != len(data) {
		return accepted, errors.New("command output limit exceeded")
	}
	return accepted, nil
}
func (c *commands) Operation(name string) Function {
	if name == "spawn" {
		return spawnOperation()
	}
	result := "@std/Result[@std/CommandOutput][@std/CommandError]"
	failure := func(tag, message string) Value {
		fields := []Value{}
		if tag == "Failed" {
			fields = append(fields, message)
		}
		return Alternative{result, "error", []Value{Alternative{"@std/CommandError", tag, fields}}}
	}
	return NewFunction([]string{"program", "arguments", "input", "max_output_bytes", "timeout"}, result, func(ctx *Execution, args []Value) Value {
		normalized, valid := nativeOptions("run", []LibraryParam{{"program", "String"}, {"arguments", "List[String]"}, {"input", "Bytes"}, {"max_output_bytes", "Optional[Int]"}, {"timeout", "Optional[Duration]"}}, args)
		if !valid {
			return failure("InvalidInput", "")
		}
		args = normalized
		program := args[0].(string)
		limit := args[3].(int64)
		timeout := args[4].(Duration)
		if program == "" || strings.ContainsRune(program, 0) || limit < 0 || timeout < nativeNoTimeout {
			return failure("InvalidInput", "")
		}
		arguments := make([]string, len(args[1].(*List).Boxed()))
		for i, arg := range args[1].(*List).Boxed() {
			arguments[i] = arg.(string)
			if strings.ContainsRune(arguments[i], 0) {
				return failure("InvalidInput", "")
			}
		}
		lifetime, stop := nativeContextTimeout(ctx.Context, time.Duration(timeout))
		defer stop()
		execution, cancel := context.WithCancel(lifetime)
		defer cancel()
		output := &boundedOutput{remaining: limit, cancel: cancel}
		command := exec.CommandContext(execution, program, arguments...)
		if hostos.SetProcessGroup(command) {
			command.Cancel = func() error {
				process, err := os.FindProcess(-command.Process.Pid)
				if err != nil {
					return err
				}
				return process.Kill()
			}
		}
		command.Stdin = bytes.NewReader(args[2].(Bytes).Items)
		command.Stdout = commandOutputWriter{output: output}
		command.Stderr = commandOutputWriter{output: output, stderr: true}
		command.WaitDelay = time.Second
		err := command.Run()
		CheckCancelled(ctx)
		if output.overflow {
			return failure("OutputLimit", "")
		}
		if lifetime.Err() != nil {
			return failure("Timeout", "")
		}
		code := int64(0)
		if err != nil {
			if exit, ok := err.(*exec.ExitError); ok {
				code = int64(exit.ExitCode())
			} else {
				if errors.Is(err, exec.ErrNotFound) || errors.Is(err, os.ErrNotExist) {
					return failure("Unavailable", "")
				}
				if errors.Is(err, exec.ErrWaitDelay) {
					return failure("Failed", "the command finished but a background process kept its output open; close or redirect its output, or set a timeout")
				}
				return failure("Failed", err.Error())
			}
		}
		return Alternative{result, "ok", []Value{Record{"@std/CommandOutput", map[string]Value{"exit_code": code, "stdout": Bytes{append([]byte{}, output.stdout.Bytes()...)}, "stderr": Bytes{append([]byte{}, output.stderr.Bytes()...)}}}}}
	})
}

// subprocess is a managed long-lived child. Its pipes are host streams owned
// by the process resource; close kills the process group and joins the child.
type subprocess struct {
	mu                    sync.Mutex
	command               *exec.Cmd
	grouped, closed       bool
	stdin, stdout, stderr *stream
	exited                chan struct{}
	status                int64
	stopCancel            func() bool
}

func spawnOperation() Function {
	result := "@std/Result[@std/Subprocess][@std/CommandError]"
	failure := func(tag, message string) Value {
		fields := []Value{}
		if tag == "Failed" {
			fields = append(fields, message)
		}
		return Alternative{result, "error", []Value{Alternative{"@std/CommandError", tag, fields}}}
	}
	body := func(ctx *Execution, args []Value) Value {
		program := args[0].(string)
		if program == "" || strings.ContainsRune(program, 0) {
			return failure("InvalidInput", "")
		}
		arguments := make([]string, len(args[1].(*List).Items))
		for i, arg := range args[1].(*List).Items {
			arguments[i] = arg.(string)
			if strings.ContainsRune(arguments[i], 0) {
				return failure("InvalidInput", "")
			}
		}
		inRead, inWrite, err := os.Pipe()
		if err != nil {
			return failure("Failed", err.Error())
		}
		outRead, outWrite, err := os.Pipe()
		if err != nil {
			inRead.Close()
			inWrite.Close()
			return failure("Failed", err.Error())
		}
		errRead, errWrite, err := os.Pipe()
		if err != nil {
			inRead.Close()
			inWrite.Close()
			outRead.Close()
			outWrite.Close()
			return failure("Failed", err.Error())
		}
		command := exec.Command(program, arguments...)
		command.Stdin, command.Stdout, command.Stderr = inRead, outWrite, errWrite
		grouped := hostos.SetProcessGroup(command)
		startErr := command.Start()
		// The child holds its own ends now; the parent keeps only its ends.
		inRead.Close()
		outWrite.Close()
		errWrite.Close()
		if startErr != nil {
			inWrite.Close()
			outRead.Close()
			errRead.Close()
			if errors.Is(startErr, exec.ErrNotFound) || errors.Is(startErr, os.ErrNotExist) {
				return failure("Unavailable", "")
			}
			return failure("Failed", startErr.Error())
		}
		const bytesResult = "@std/Result[@std/Optional[@std/Bytes]][@std/IoError]"
		p := &subprocess{
			command: command, grouped: grouped, exited: make(chan struct{}),
			stdin:  &stream{file: inWrite, owned: true, resultType: "@std/Result[Unit][@std/IoError]"},
			stdout: &stream{file: outRead, owned: true, resultType: bytesResult},
			stderr: &stream{file: errRead, owned: true, resultType: bytesResult},
		}
		go func() {
			err := command.Wait()
			p.status = int64(command.ProcessState.ExitCode())
			_ = err
			close(p.exited)
		}()
		// Cancelling the acquiring execution tears down the whole tree.
		p.stopCancel = context.AfterFunc(ctx.Context, func() { p.signal(true) })
		return Alternative{result, "ok", []Value{ViewOf("@std/Subprocess", p)}}
	}
	return NewAcquisition([]string{"program", "arguments"}, result, body, func(ctx *Execution, value Value) {
		if alt, ok := value.(Alternative); ok && alt.Tag == "ok" {
			Invoke(Shield(ctx), Bind(alt.Fields[0], "", "close"), nil)
		}
	})
}

// signal terminates the child, or its whole process group where supported.
func (p *subprocess) signal(force bool) {
	select {
	case <-p.exited:
		return
	default:
	}
	pid := p.command.Process.Pid
	if p.grouped {
		pid = -pid
	}
	process, err := os.FindProcess(pid)
	if err != nil {
		return
	}
	if !force {
		if process.Signal(syscall.SIGTERM) == nil {
			return
		}
	}
	process.Kill()
}

func (p *subprocess) close() {
	p.mu.Lock()
	first := !p.closed
	p.closed = true
	p.mu.Unlock()
	if first {
		p.stopCancel()
		p.signal(true)
		// Descendants may outlive the leader in the group; kill after the
		// leader is reaped as well so no group member survives the scope.
		<-p.exited
		if p.grouped {
			if process, err := os.FindProcess(-p.command.Process.Pid); err == nil {
				process.Kill()
			}
		}
	}
	p.stdin.close()
	p.stdout.close()
	p.stderr.close()
	<-p.exited
}

func (p *subprocess) Operation(name string) Function {
	switch name {
	case "stdin":
		return NewFunction(nil, "@std/WriteStream", func(*Execution, []Value) Value { return ViewOf("@std/WriteStream", p.stdin) })
	case "stdout":
		return NewFunction(nil, "@std/ReadStream", func(*Execution, []Value) Value { return ViewOf("@std/ReadStream", p.stdout) })
	case "stderr":
		return NewFunction(nil, "@std/ReadStream", func(*Execution, []Value) Value { return ViewOf("@std/ReadStream", p.stderr) })
	case "close":
		return NewFunction(nil, "Unit", func(*Execution, []Value) Value { p.close(); return Unit{} })
	case "terminate", "kill":
		return NewFunction(nil, "Unit", func(*Execution, []Value) Value { p.signal(name == "kill"); return Unit{} })
	case "wait":
		result := "@std/Result[Int][@std/CommandError]"
		return NewFunction([]string{"timeout"}, result, func(ctx *Execution, args []Value) Value {
			normalized, valid := nativeOptions("wait", []LibraryParam{{"timeout", "Optional[Duration]"}}, args)
			timeout := Duration(0)
			if valid {
				timeout = normalized[0].(Duration)
			}
			if !valid || timeout < nativeNoTimeout {
				return Alternative{result, "error", []Value{Alternative{"@std/CommandError", "InvalidInput", []Value{}}}}
			}
			lifetime, stop := nativeContextTimeout(ctx.Context, time.Duration(timeout))
			defer stop()
			select {
			case <-p.exited:
				CheckCancelled(ctx)
				return Alternative{result, "ok", []Value{p.status}}
			case <-lifetime.Done():
				CheckCancelled(ctx)
				return Alternative{result, "error", []Value{Alternative{"@std/CommandError", "TimedOut", []Value{}}}}
			}
		})
	}
	return Function{}
}
