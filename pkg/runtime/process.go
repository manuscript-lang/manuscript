package msruntime

import (
	"bytes"
	"context"
	"errors"
	"os"
	"os/exec"
	"os/signal"
	"os/user"
	"path/filepath"
	goruntime "runtime"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"
	"unicode/utf8"

	"github.com/manuscript-lang/manuscript/internal/hostos"
	memstats "github.com/shirou/gopsutil/v4/mem"
	processstats "github.com/shirou/gopsutil/v4/process"
)

var processStarted = time.Now()
var environmentMu sync.Mutex

func procErrorOf(err error) ProcessError {
	switch classifyOS(err, false) {
	case kindInvalidInput:
		return ProcessError_InvalidInput{}
	case kindUnsupported:
		return ProcessError_Unsupported{}
	case kindNotFound:
		return ProcessError_NotFound{}
	case kindAlreadyExists:
		return ProcessError_AlreadyExists{}
	case kindPermissionDenied:
		return ProcessError_PermissionDenied{}
	}
	return ProcessError_Failed{Message: err.Error()}
}

func procFail[T any](e ProcessError) Result[T, ProcessError] { return Fail[T, ProcessError](e) }
func procInvalid[T any]() Result[T, ProcessError]            { return procFail[T](ProcessError_InvalidInput{}) }
func procOK[T any](v T) Result[T, ProcessError]              { return Ok[T, ProcessError](v) }

func procDone[T any](value T, err error) Result[T, ProcessError] {
	if err != nil {
		return procFail[T](procErrorOf(err))
	}
	return procOK(value)
}

func procText(s string, err error) Result[string, ProcessError] {
	if err == nil && !utf8.ValidString(s) {
		return procFail[string](ProcessError_Unsupported{})
	}
	return procDone(s, err)
}

// osProcessControl is the host's process-wide control surface.
type osProcessControl struct{}

var _ ProcessControl = osProcessControl{}

func (osProcessControl) MonotonicTime(ctx *Execution) int {
	CheckCancelled(ctx)
	return FitInt(int64(time.Since(processStarted)))
}

func (osProcessControl) WatchSignals(ctx *Execution, signals *List[int], capacity Option[int]) Result[SignalStream, ProcessError] {
	CheckCancelled(ctx)
	n, ok := optionLimit(capacity, 128)
	if !ok || n <= 0 || n > 1048576 {
		return procInvalid[SignalStream]()
	}
	var list []os.Signal
	for _, v := range signals.Items {
		if v <= 0 || v > 64 || v == int(syscall.SIGKILL) || int64(v) == hostos.Constants()["SIGSTOP"] {
			return procInvalid[SignalStream]()
		}
		list = append(list, syscall.Signal(v))
	}
	if len(list) == 0 {
		return procInvalid[SignalStream]()
	}
	stream := &osSignalStream{events: make(chan os.Signal, int(n)), done: make(chan struct{}), gate: make(chan struct{}, 1)}
	signal.Notify(stream.events, list...)
	return procOK[SignalStream](stream)
}

// memoryLimit resolves the process's own cgroup path; it does not substitute
// the cgroup mount root when the process is in a nested group. cgroup v1 and
// v2 are both supported.
func memoryLimit() (limit, current int, err error) {
	if goruntime.GOOS != "linux" {
		return 0, 0, nil
	}
	data, err := os.ReadFile("/proc/self/cgroup")
	if err != nil {
		return 0, 0, err
	}
	for _, line := range strings.Split(string(data), "\n") {
		parts := strings.SplitN(line, ":", 3)
		if len(parts) != 3 {
			continue
		}
		base := ""
		limitFile, currentFile := "memory.max", "memory.current"
		if parts[0] == "0" && parts[1] == "" {
			base = "/sys/fs/cgroup"
		} else {
			for _, controller := range strings.Split(parts[1], ",") {
				if controller == "memory" {
					base = "/sys/fs/cgroup/memory"
					limitFile, currentFile = "memory.limit_in_bytes", "memory.usage_in_bytes"
				}
			}
		}
		if base == "" {
			continue
		}
		clean := filepath.Clean("/" + parts[2])
		base = filepath.Join(base, strings.TrimPrefix(clean, "/"))
		limitData, err := os.ReadFile(filepath.Join(base, limitFile))
		if errors.Is(err, os.ErrNotExist) {
			return 0, 0, nil
		}
		if err != nil {
			return 0, 0, err
		}
		text := strings.TrimSpace(string(limitData))
		if text == "max" {
			return 0, 0, nil
		}
		limit, err := strconv.ParseInt(text, 10, 64)
		if err != nil || limit < 0 {
			return 0, 0, errors.New("invalid cgroup memory limit")
		}
		if limit >= 1<<60 {
			return 0, 0, nil
		}
		currentData, err := os.ReadFile(filepath.Join(base, currentFile))
		if err != nil {
			return 0, 0, err
		}
		current, err := strconv.ParseInt(strings.TrimSpace(string(currentData)), 10, 64)
		if err != nil || current < 0 {
			return 0, 0, errors.New("invalid cgroup memory usage")
		}
		return clampInt(limit), clampInt(current), nil
	}
	return 0, 0, nil
}

func (osProcessControl) ConstrainedMemory(ctx *Execution) Result[int, ProcessError] {
	CheckCancelled(ctx)
	limit, _, err := memoryLimit()
	return procDone(limit, err)
}

func (osProcessControl) AvailableMemory(ctx *Execution) Result[int, ProcessError] {
	CheckCancelled(ctx)
	limit, current, err := memoryLimit()
	if err != nil {
		return procDone(int(0), err)
	}
	memory, err := memstats.VirtualMemoryWithContext(ctx.Context)
	CheckCancelled(ctx)
	if err != nil {
		return procDone(int(0), err)
	}
	available := int(memory.Available)
	if limit > 0 {
		available = min(available, max(limit-current, 0))
	}
	return procOK(available)
}

func (osProcessControl) Title(ctx *Execution) Result[string, ProcessError] {
	CheckCancelled(ctx)
	value, err := hostos.ProcessTitle()
	return procText(value, err)
}

func (osProcessControl) SetTitle(ctx *Execution, title string) Result[Unit, ProcessError] {
	CheckCancelled(ctx)
	if strings.ContainsAny(title, "\x00\n") {
		return procInvalid[Unit]()
	}
	return procDone(Unit{}, hostos.SetProcessTitle(title))
}

func (osProcessControl) InitializeGroups(ctx *Execution, username string, gid int) Result[Unit, ProcessError] {
	CheckCancelled(ctx)
	if gid < 0 || gid > 2147483647 || strings.ContainsRune(username, 0) {
		return procInvalid[Unit]()
	}
	u, err := user.Lookup(username)
	if err != nil {
		return procDone(Unit{}, err)
	}
	names, err := u.GroupIds()
	if err != nil {
		return procDone(Unit{}, err)
	}
	groups := []int{int(gid)}
	seen := map[int]bool{int(gid): true}
	for _, name := range names {
		id, err := strconv.ParseInt(name, 10, 32)
		if err != nil || id < 0 {
			return procFail[Unit](ProcessError_InvalidData{})
		}
		if !seen[int(id)] {
			groups = append(groups, int(id))
			seen[int(id)] = true
		}
	}
	return procDone(Unit{}, hostos.SetGroups(groups))
}

func (osProcessControl) Replace(ctx *Execution, program string, arguments *List[string], environment *Map[string, string]) Result[Unit, ProcessError] {
	CheckCancelled(ctx)
	env := []string{}
	if program == "" || strings.ContainsRune(program, 0) || len(arguments.Items) == 0 {
		return procInvalid[Unit]()
	}
	for _, arg := range arguments.Items {
		if strings.ContainsRune(arg, 0) {
			return procInvalid[Unit]()
		}
	}
	for _, entry := range environment.Snapshot() {
		if entry.Key == "" || strings.ContainsAny(entry.Key, "=\x00") || strings.ContainsRune(entry.Value, 0) {
			return procInvalid[Unit]()
		}
		env = append(env, entry.Key+"="+entry.Value)
	}
	CheckCancelled(ctx)
	return procDone(Unit{}, hostos.Exec(program, arguments.Items, env))
}

func (osProcessControl) Info(ctx *Execution) Result[*ProcessInfo, ProcessError] {
	CheckCancelled(ctx)
	executable, err := os.Executable()
	if err != nil {
		return procDone[*ProcessInfo](nil, err)
	}
	if !utf8.ValidString(executable + strings.Join(os.Args, "")) {
		return procFail[*ProcessInfo](ProcessError_Unsupported{})
	}
	return procOK(&ProcessInfo{Pid: int(os.Getpid()), ParentPid: int(os.Getppid()), Executable: executable, Arguments: NewList(os.Args...), Os: goruntime.GOOS, Architecture: goruntime.GOARCH, Uid: int(os.Getuid()), Gid: int(os.Getgid()), EffectiveUid: int(os.Geteuid()), EffectiveGid: int(os.Getegid())})
}

func (osProcessControl) MemoryUsage(ctx *Execution) Result[*MemoryUsage, ProcessError] {
	CheckCancelled(ctx)
	var mem goruntime.MemStats
	goruntime.ReadMemStats(&mem)
	p, err := processstats.NewProcessWithContext(ctx.Context, int32(os.Getpid()))
	if err != nil {
		return procDone[*MemoryUsage](nil, err)
	}
	memory, err := p.MemoryInfoWithContext(ctx.Context)
	CheckCancelled(ctx)
	if err != nil {
		return procDone[*MemoryUsage](nil, err)
	}
	return procOK(&MemoryUsage{HeapUsed: int(mem.HeapAlloc), HeapTotal: int(mem.HeapInuse), HeapSystem: int(mem.HeapSys), External: int(mem.Sys - mem.HeapSys), Resident: int(memory.RSS)})
}

func (osProcessControl) CpuUsage(ctx *Execution) Result[*CpuUsage, ProcessError] {
	CheckCancelled(ctx)
	usage, err := hostos.ResourceUsage()
	if err != nil {
		return procDone[*CpuUsage](nil, err)
	}
	return procOK(&CpuUsage{UserMicroseconds: FitInt(usage.User), SystemMicroseconds: FitInt(usage.System)})
}

func (osProcessControl) Uptime(ctx *Execution) Result[Duration, ProcessError] {
	CheckCancelled(ctx)
	return procOK(Duration(time.Since(processStarted)))
}

func (osProcessControl) Environment(ctx *Execution) Result[*Map[string, string], ProcessError] {
	CheckCancelled(ctx)
	environmentMu.Lock()
	defer environmentMu.Unlock()
	env := NewMap[string, string]()
	for _, entry := range os.Environ() {
		if !utf8.ValidString(entry) {
			return procFail[*Map[string, string]](ProcessError_Unsupported{})
		}
		if key, value, ok := strings.Cut(entry, "="); ok {
			env.Put(key, value)
		}
	}
	return procOK(env)
}

func (osProcessControl) SetEnvironment(ctx *Execution, name string, value Option[string]) Result[Unit, ProcessError] {
	CheckCancelled(ctx)
	if name == "" || strings.ContainsAny(name, "=\x00") {
		return procInvalid[Unit]()
	}
	environmentMu.Lock()
	defer environmentMu.Unlock()
	var err error
	if value.Some {
		if strings.ContainsRune(value.Val, 0) {
			return procInvalid[Unit]()
		}
		err = os.Setenv(name, value.Val)
	} else {
		err = os.Unsetenv(name)
	}
	return procDone(Unit{}, err)
}

func (osProcessControl) LoadEnvironment(ctx *Execution, path string, maxBytes Option[int]) Result[Unit, ProcessError] {
	CheckCancelled(ctx)
	limit, ok := optionLimit(maxBytes, unlimited)
	if !ok || strings.ContainsRune(path, 0) {
		return procInvalid[Unit]()
	}
	file, err := os.Open(path)
	if err != nil {
		return procDone(Unit{}, err)
	}
	defer file.Close()
	data, code := readBounded(ctx, file, limit)
	switch code {
	case "LimitExceeded":
		return procFail[Unit](ProcessError_LimitExceeded{})
	case "InvalidData":
		return procFail[Unit](ProcessError_InvalidData{})
	case "Failed":
		return procFail[Unit](ProcessError_Failed{})
	}
	if !utf8.Valid(data) {
		return procFail[Unit](ProcessError_InvalidData{})
	}
	entries, ok := parseEnvironment(string(data))
	if !ok {
		return procFail[Unit](ProcessError_InvalidData{})
	}
	environmentMu.Lock()
	defer environmentMu.Unlock()
	for _, e := range entries {
		if _, exists := os.LookupEnv(e.Key); !exists {
			if err := os.Setenv(e.Key, e.Value); err != nil {
				return procDone(Unit{}, err)
			}
		}
	}
	return procOK(Unit{})
}

func (osProcessControl) WorkingDirectory(ctx *Execution) Result[string, ProcessError] {
	CheckCancelled(ctx)
	workingDirectoryMu.Lock()
	defer workingDirectoryMu.Unlock()
	v, err := os.Getwd()
	return procText(v, err)
}

func (osProcessControl) ChangeDirectory(ctx *Execution, path string) Result[Unit, ProcessError] {
	CheckCancelled(ctx)
	if strings.ContainsRune(path, 0) {
		return procInvalid[Unit]()
	}
	workingDirectoryMu.Lock()
	defer workingDirectoryMu.Unlock()
	return procDone(Unit{}, os.Chdir(path))
}

func (osProcessControl) SendSignal(ctx *Execution, pid, sig int) Result[Unit, ProcessError] {
	CheckCancelled(ctx)
	if pid < -2147483648 || pid > 2147483647 || sig < 0 || sig > 64 {
		return procInvalid[Unit]()
	}
	return procDone(Unit{}, hostos.SendSignal(int(pid), int(sig)))
}

func (osProcessControl) Groups(ctx *Execution) Result[*List[int], ProcessError] {
	CheckCancelled(ctx)
	if goruntime.GOOS == "windows" {
		return procFail[*List[int]](ProcessError_Unsupported{})
	}
	groups, err := os.Getgroups()
	if err != nil {
		return procDone[*List[int]](nil, err)
	}
	items := make([]int, len(groups))
	for i, g := range groups {
		items[i] = int(g)
	}
	return procOK(NewList(items...))
}

func (osProcessControl) ResourceUsage(ctx *Execution) Result[*ResourceUsage, ProcessError] {
	CheckCancelled(ctx)
	u, err := hostos.ResourceUsage()
	if err != nil {
		return procDone[*ResourceUsage](nil, err)
	}
	return procOK(&ResourceUsage{UserMicroseconds: FitInt(u.User), SystemMicroseconds: FitInt(u.System), MaxResidentBytes: clampInt(u.MaxRSS), MinorFaults: clampInt(u.MinorFaults), MajorFaults: clampInt(u.MajorFaults), FilesystemReads: clampInt(u.Reads), FilesystemWrites: clampInt(u.Writes), VoluntarySwitches: clampInt(u.VoluntarySwitches), InvoluntarySwitches: clampInt(u.InvoluntarySwitches)})
}

func (osProcessControl) Umask(ctx *Execution, mask int) Result[int, ProcessError] {
	CheckCancelled(ctx)
	if mask < 0 || mask > 0777 {
		return procInvalid[int]()
	}
	workingDirectoryMu.Lock()
	v := hostos.Umask(int(mask))
	workingDirectoryMu.Unlock()
	if v < 0 {
		return procFail[int](ProcessError_Unsupported{})
	}
	return procOK(int(v))
}

func (osProcessControl) SetIdentity(ctx *Execution, kind string, id int) Result[Unit, ProcessError] {
	CheckCancelled(ctx)
	if id < 0 || id > 2147483647 || (kind != "uid" && kind != "gid" && kind != "euid" && kind != "egid") {
		return procInvalid[Unit]()
	}
	return procDone(Unit{}, hostos.SetIdentity(kind, int(id)))
}

func (osProcessControl) SetGroups(ctx *Execution, groups *List[int]) Result[Unit, ProcessError] {
	CheckCancelled(ctx)
	var list []int
	for _, id := range groups.Items {
		if id < 0 || id > 2147483647 {
			return procInvalid[Unit]()
		}
		list = append(list, int(id))
	}
	return procDone(Unit{}, hostos.SetGroups(list))
}

type envEntry struct{ Key, Value string }

// parseEnvironment parses fully before the environment is mutated. Existing
// variables win. Quoted values can span lines; comments outside quotes and an
// export prefix are accepted.
func parseEnvironment(text string) ([]envEntry, bool) {
	text = strings.TrimPrefix(text, "\xef\xbb\xbf")
	var entries []envEntry
	for len(text) > 0 {
		text = strings.TrimLeft(text, " \t\r\n")
		if text == "" {
			break
		}
		if text[0] == '#' {
			_, rest, _ := strings.Cut(text, "\n")
			text = rest
			continue
		}
		text = strings.TrimPrefix(text, "export ")
		at := strings.IndexByte(text, '=')
		if at < 1 {
			return nil, false
		}
		key := strings.TrimSpace(text[:at])
		if strings.ContainsAny(key, " \t\r\n\x00") {
			return nil, false
		}
		for i, c := range key {
			if !(c == '_' || c >= 'A' && c <= 'Z' || c >= 'a' && c <= 'z' || i > 0 && c >= '0' && c <= '9') {
				return nil, false
			}
		}
		text = strings.TrimLeft(text[at+1:], " \t")
		value := ""
		if text != "" && (text[0] == '\'' || text[0] == '"' || text[0] == '`') {
			quote := text[0]
			end := strings.IndexByte(text[1:], quote)
			if end < 0 {
				return nil, false
			}
			value = text[1 : end+1]
			text = text[end+2:]
			line, rest, _ := strings.Cut(text, "\n")
			line = strings.TrimSpace(line)
			if line != "" && !strings.HasPrefix(line, "#") {
				return nil, false
			}
			text = rest
		} else {
			line, rest, _ := strings.Cut(text, "\n")
			line, _, _ = strings.Cut(line, "#")
			value = strings.TrimSpace(line)
			text = rest
		}
		if strings.ContainsRune(value, 0) {
			return nil, false
		}
		entries = append(entries, envEntry{key, value})
	}
	return entries, true
}

// osSignalStream delivers process signals one at a time.
type osSignalStream struct {
	mu     sync.Mutex
	closed bool
	events chan os.Signal
	done   chan struct{}
	gate   chan struct{}
}

var _ SignalStream = (*osSignalStream)(nil)

func (s *osSignalStream) Close(*Execution) Unit {
	s.mu.Lock()
	if !s.closed {
		s.closed = true
		close(s.done)
	}
	s.mu.Unlock()
	signal.Stop(s.events)
	s.gate <- struct{}{}
	<-s.gate
	return Unit{}
}

func (s *osSignalStream) Next(ctx *Execution) Result[int, ProcessError] {
	select {
	case s.gate <- struct{}{}:
	case <-s.done:
		return procFail[int](ProcessError_Closed{})
	case <-ctx.Context.Done():
		CheckCancelled(ctx)
	}
	defer func() { <-s.gate }()
	select {
	case <-s.done:
		return procFail[int](ProcessError_Closed{})
	case <-ctx.Context.Done():
		CheckCancelled(ctx)
	case value := <-s.events:
		CheckCancelled(ctx)
		return procOK(int(value.(syscall.Signal)))
	}
	Raise("unreachable signal wait")
	return procFail[int](ProcessError_Closed{})
}

// Commands.

type osCommands struct{}

var _ Commands = osCommands{}

func cmdFail[T any](e CommandError) Result[T, CommandError] { return Fail[T, CommandError](e) }

// boundedOutput collects a command's output up to a byte budget.
type boundedOutput struct {
	mu             sync.Mutex
	remaining      int
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
	if int(accepted) > output.remaining {
		accepted = int(output.remaining)
		output.overflow = true
		output.cancel()
	}
	if w.stderr {
		output.stderr.Write(data[:accepted])
	} else {
		output.stdout.Write(data[:accepted])
	}
	output.remaining -= int(accepted)
	if accepted != len(data) {
		return accepted, errors.New("command output limit exceeded")
	}
	return accepted, nil
}

// noTimeout marks an absent timeout.
const noTimeout = Duration(-1)

func contextTimeout(parent context.Context, timeout time.Duration) (context.Context, context.CancelFunc) {
	if timeout < 0 {
		return context.WithCancel(parent)
	}
	return context.WithTimeout(parent, timeout)
}

// optionTimeout resolves an optional timeout: none is no deadline, a negative
// value is invalid.
func optionTimeout(v Option[Duration]) (Duration, bool) {
	if !v.Some {
		return noTimeout, true
	}
	return v.Val, v.Val >= 0
}

func validArguments(arguments *List[string]) ([]string, bool) {
	out := make([]string, len(arguments.Items))
	for i, arg := range arguments.Items {
		out[i] = arg
		if strings.ContainsRune(arg, 0) {
			return nil, false
		}
	}
	return out, true
}

func (osCommands) Run(ctx *Execution, program string, arguments *List[string], input *Bytes, maxOutput Option[int], timeoutOption Option[Duration]) Result[*CommandOutput, CommandError] {
	limit, ok := optionLimit(maxOutput, unlimited)
	timeout, ok2 := optionTimeout(timeoutOption)
	if !ok || !ok2 || program == "" || strings.ContainsRune(program, 0) {
		return cmdFail[*CommandOutput](CommandError_InvalidInput{})
	}
	args, valid := validArguments(arguments)
	if !valid {
		return cmdFail[*CommandOutput](CommandError_InvalidInput{})
	}
	lifetime, stop := contextTimeout(ctx.Context, time.Duration(timeout))
	defer stop()
	execution, cancel := context.WithCancel(lifetime)
	defer cancel()
	output := &boundedOutput{remaining: limit, cancel: cancel}
	command := exec.CommandContext(execution, program, args...)
	if hostos.SetProcessGroup(command) {
		command.Cancel = func() error {
			process, err := os.FindProcess(-command.Process.Pid)
			if err != nil {
				return err
			}
			return process.Kill()
		}
	}
	command.Stdin = bytes.NewReader(input.Data)
	command.Stdout = commandOutputWriter{output: output}
	command.Stderr = commandOutputWriter{output: output, stderr: true}
	command.WaitDelay = time.Second
	err := command.Run()
	CheckCancelled(ctx)
	if output.overflow {
		return cmdFail[*CommandOutput](CommandError_OutputLimit{})
	}
	if lifetime.Err() != nil {
		return cmdFail[*CommandOutput](CommandError_Timeout{})
	}
	code := 0
	if err != nil {
		if exit, ok := err.(*exec.ExitError); ok {
			code = int(exit.ExitCode())
		} else {
			if errors.Is(err, exec.ErrNotFound) || errors.Is(err, os.ErrNotExist) {
				return cmdFail[*CommandOutput](CommandError_Unavailable{})
			}
			if errors.Is(err, exec.ErrWaitDelay) {
				return cmdFail[*CommandOutput](CommandError_Failed{Message: "the command finished but a background process kept its output open; close or redirect its output, or set a timeout"})
			}
			return cmdFail[*CommandOutput](CommandError_Failed{Message: err.Error()})
		}
	}
	return Ok[*CommandOutput, CommandError](&CommandOutput{ExitCode: code, Stdout: NewBytes(append([]byte{}, output.stdout.Bytes()...)), Stderr: NewBytes(append([]byte{}, output.stderr.Bytes()...))})
}

// osSubprocess is a managed long-lived child. Its pipes are host streams owned
// by the process resource; Close kills the process group and joins the child.
type osSubprocess struct {
	mu                    sync.Mutex
	command               *exec.Cmd
	grouped, closed       bool
	stdin, stdout, stderr *hostStream
	exited                chan struct{}
	status                int
	stopCancel            func() bool
}

var _ Subprocess = (*osSubprocess)(nil)

func (osCommands) Spawn(ctx *Execution, program string, arguments *List[string]) Result[Subprocess, CommandError] {
	if program == "" || strings.ContainsRune(program, 0) {
		return cmdFail[Subprocess](CommandError_InvalidInput{})
	}
	args, valid := validArguments(arguments)
	if !valid {
		return cmdFail[Subprocess](CommandError_InvalidInput{})
	}
	failed := func(err error) Result[Subprocess, CommandError] {
		return cmdFail[Subprocess](CommandError_Failed{Message: err.Error()})
	}
	inRead, inWrite, err := os.Pipe()
	if err != nil {
		return failed(err)
	}
	outRead, outWrite, err := os.Pipe()
	if err != nil {
		inRead.Close()
		inWrite.Close()
		return failed(err)
	}
	errRead, errWrite, err := os.Pipe()
	if err != nil {
		inRead.Close()
		inWrite.Close()
		outRead.Close()
		outWrite.Close()
		return failed(err)
	}
	command := exec.Command(program, args...)
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
			return cmdFail[Subprocess](CommandError_Unavailable{})
		}
		return failed(startErr)
	}
	p := &osSubprocess{command: command, grouped: grouped, exited: make(chan struct{}), stdin: newHostStream(inWrite, true), stdout: newHostStream(outRead, true), stderr: newHostStream(errRead, true)}
	go func() {
		command.Wait()
		p.status = int(command.ProcessState.ExitCode())
		close(p.exited)
	}()
	// Cancelling the acquiring execution tears down the whole tree.
	p.stopCancel = context.AfterFunc(ctx.Context, func() { p.signal(true) })
	return Ok[Subprocess, CommandError](p)
}

// signal terminates the child, or its whole process group where supported.
func (p *osSubprocess) signal(force bool) {
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

func (p *osSubprocess) Stdin(*Execution) WriteStream { return p.stdin }
func (p *osSubprocess) Stdout(*Execution) ReadStream { return p.stdout }
func (p *osSubprocess) Stderr(*Execution) ReadStream { return p.stderr }

func (p *osSubprocess) Terminate(*Execution) Unit { p.signal(false); return Unit{} }
func (p *osSubprocess) Kill(*Execution) Unit      { p.signal(true); return Unit{} }

func (p *osSubprocess) Close(ctx *Execution) Unit {
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
	p.stdin.Close(ctx)
	p.stdout.Close(ctx)
	p.stderr.Close(ctx)
	<-p.exited
	return Unit{}
}

func (p *osSubprocess) Wait(ctx *Execution, timeoutOption Option[Duration]) Result[int, CommandError] {
	timeout, ok := optionTimeout(timeoutOption)
	if !ok {
		return cmdFail[int](CommandError_InvalidInput{})
	}
	lifetime, stop := contextTimeout(ctx.Context, time.Duration(timeout))
	defer stop()
	select {
	case <-p.exited:
		CheckCancelled(ctx)
		return Ok[int, CommandError](p.status)
	case <-lifetime.Done():
		CheckCancelled(ctx)
		return cmdFail[int](CommandError_Timeout{})
	}
}
