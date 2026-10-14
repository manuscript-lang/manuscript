package msruntime

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"reflect"
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
		arguments := make([]string, len(args[1].(*List).Items))
		for i, arg := range args[1].(*List).Items {
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
		command.SysProcAttr = &syscall.SysProcAttr{}
		group := reflect.ValueOf(command.SysProcAttr).Elem().FieldByName("Setpgid")
		if group.IsValid() && group.CanSet() {
			group.SetBool(true)
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
