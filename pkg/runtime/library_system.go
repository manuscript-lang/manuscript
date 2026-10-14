//go:build !ms_lean

package msruntime

import (
	"errors"
	"net"
	"os"
	"os/user"
	"path/filepath"
	goruntime "runtime"
	"strconv"
	"strings"
	"sync"
	"time"
	"unicode/utf8"

	"github.com/manuscript-lang/manuscript/internal/hostos"
	cpustats "github.com/shirou/gopsutil/v4/cpu"
	hoststats "github.com/shirou/gopsutil/v4/host"
	loadstats "github.com/shirou/gopsutil/v4/load"
	memstats "github.com/shirou/gopsutil/v4/mem"
	processstats "github.com/shirou/gopsutil/v4/process"
)

var libraryProcessStarted = time.Now()
var libraryEnvironmentMu sync.Mutex

func init() {
	libraryAdd("system", "os_type", "String", nil, func(_ *Execution, _ string, _ []Value) Value {
		names := map[string]string{"linux": "Linux", "darwin": "Darwin", "windows": "Windows_NT"}
		if name := names[goruntime.GOOS]; name != "" {
			return name
		}
		return goruntime.GOOS
	})
	libraryAdd("system", "constants", "Map[String][Int]", nil, func(_ *Execution, _ string, _ []Value) Value {
		values := hostos.Constants()
		return libraryConstants(values)
	})
	LibraryMethods = append(LibraryMethods, []LibraryMethod{
		{"ProcessControl", "monotonic_time", "Int", nil},
		{"ProcessControl", "constrained_memory", libraryResult("Int", "ProcessError"), nil},
		{"ProcessControl", "available_memory", libraryResult("Int", "ProcessError"), nil},
		{"ProcessControl", "title", libraryResult("String", "ProcessError"), nil},
		{"ProcessControl", "set_title", libraryResult("Unit", "ProcessError"), []LibraryParam{{"title", "String"}}},
		{"ProcessControl", "initialize_groups", libraryResult("Unit", "ProcessError"), []LibraryParam{{"username", "String"}, {"gid", "Int"}}},
		{"ProcessControl", "replace", libraryResult("Unit", "ProcessError"), []LibraryParam{{"program", "String"}, {"arguments", "List[String]"}, {"environment", "Map[String][String]"}}}, {"System", "get_priority", libraryResult("Int", "SystemError"), []LibraryParam{{"pid", "Int"}}}, {"System", "set_priority", libraryResult("Unit", "SystemError"), []LibraryParam{{"pid", "Int"}, {"priority", "Int"}}}, {"ProcessControl", "resource_usage", libraryResult("ResourceUsage", "ProcessError"), []LibraryParam{}}, {"ProcessControl", "umask", libraryResult("Int", "ProcessError"), []LibraryParam{{"mask", "Int"}}}, {"ProcessControl", "set_identity", libraryResult("Unit", "ProcessError"), []LibraryParam{{"kind", "String"}, {"id", "Int"}}}, {"ProcessControl", "set_groups", libraryResult("Unit", "ProcessError"), []LibraryParam{{"groups", "List[Int]"}}}}...)

	LibraryMethods = append(LibraryMethods, []LibraryMethod{
		{"System", "hostname", libraryResult("String", "SystemError"), []LibraryParam{}},
		{"System", "home_directory", libraryResult("String", "SystemError"), []LibraryParam{}},
		{"System", "temporary_directory", libraryResult("String", "SystemError"), []LibraryParam{}},
		{"System", "user_info", libraryResult("UserInfo", "SystemError"), []LibraryParam{}},
		{"System", "network_interfaces", libraryResult("List[NetworkInterface]", "SystemError"), []LibraryParam{}},
		{"System", "cpus", libraryResult("List[CpuInfo]", "SystemError"), []LibraryParam{}},
		{"System", "metrics", libraryResult("SystemMetrics", "SystemError"), []LibraryParam{}},
		{"System", "os_release", libraryResult("String", "SystemError"), []LibraryParam{}},
		{"System", "os_version", libraryResult("String", "SystemError"), []LibraryParam{}},
		{"System", "machine", libraryResult("String", "SystemError"), []LibraryParam{}},
		{"ProcessControl", "info", libraryResult("ProcessInfo", "ProcessError"), []LibraryParam{}},
		{"ProcessControl", "memory_usage", libraryResult("MemoryUsage", "ProcessError"), []LibraryParam{}},
		{"ProcessControl", "cpu_usage", libraryResult("CpuUsage", "ProcessError"), []LibraryParam{}},
		{"ProcessControl", "uptime", libraryResult("Duration", "ProcessError"), []LibraryParam{}},
		{"ProcessControl", "environment", libraryResult("Map[String][String]", "ProcessError"), []LibraryParam{}},
		{"ProcessControl", "set_environment", libraryResult("Unit", "ProcessError"), []LibraryParam{{"name", "String"}, {"value", "Optional[String]"}}},
		{"ProcessControl", "load_environment", libraryResult("Unit", "ProcessError"), []LibraryParam{{"path", "String"}, {"max_bytes", "Optional[Int]"}}},
		{"ProcessControl", "working_directory", libraryResult("String", "ProcessError"), []LibraryParam{}},
		{"ProcessControl", "change_directory", libraryResult("Unit", "ProcessError"), []LibraryParam{{"path", "String"}}},
		{"ProcessControl", "send_signal", libraryResult("Unit", "ProcessError"), []LibraryParam{{"pid", "Int"}, {"signal", "Int"}}},
		{"ProcessControl", "groups", libraryResult("List[Int]", "ProcessError"), []LibraryParam{}},
	}...)

	for _, name := range []string{"endianness", "end_of_line", "dev_null"} {
		n := name
		libraryAdd("system", n, "String", nil, func(_ *Execution, _ string, _ []Value) Value {
			switch n {
			case "dev_null":
				return os.DevNull
			case "end_of_line":
				if goruntime.GOOS == "windows" {
					return "\r\n"
				}
				return "\n"
			default:
				if goruntime.GOARCH == "s390x" || goruntime.GOARCH == "ppc64" || goruntime.GOARCH == "mips" || goruntime.GOARCH == "mips64" {
					return "BE"
				}
				return "LE"
			}
		})
	}
}

func libraryUTF8Result(r, s string, err error) Value {
	if err == nil && !utf8.ValidString(s) {
		return libraryError(r, "Unsupported", "")
	}
	return libraryOSResult(r, s, err)
}
func (s *librarySystem) extended(ctx *Execution, r, name string, a []Value) Value {
	CheckCancelled(ctx)
	switch name {
	case "get_priority":
		pid := a[0].(int64)
		if pid < 0 || pid > 2147483647 {
			return libraryError(r, "InvalidInput", "")
		}
		v, err := hostos.GetPriority(int(pid))
		return libraryOSResult(r, int64(v), err)
	case "set_priority":
		pid, priority := a[0].(int64), a[1].(int64)
		if pid < 0 || pid > 2147483647 || priority < -20 || priority > 19 {
			return libraryError(r, "InvalidInput", "")
		}
		return libraryOSResult(r, Unit{}, hostos.SetPriority(int(pid), int(priority)))
	case "hostname":
		v, err := os.Hostname()
		return libraryUTF8Result(r, v, err)
	case "home_directory":
		v, err := os.UserHomeDir()
		return libraryUTF8Result(r, v, err)
	case "temporary_directory":
		return libraryUTF8Result(r, os.TempDir(), nil)
	case "user_info":
		u, err := hostos.CurrentUser()
		if err != nil {
			return libraryOSResult(r, nil, err)
		}
		uid, gid := u.UID, u.GID
		shell := u.Shell
		if shell == "" && goruntime.GOOS == "linux" {
			if data, err := os.ReadFile("/etc/passwd"); err == nil {
				for _, line := range strings.Split(string(data), "\n") {
					fields := strings.Split(line, ":")
					if len(fields) == 7 && fields[0] == u.Username {
						shell = fields[6]
						break
					}
				}
			}
		}

		if !utf8.ValidString(u.Username + u.Home + shell) {
			return libraryError(r, "Unsupported", "")
		}
		return libraryOK(r, Record{"@std/UserInfo", map[string]Value{"username": u.Username, "uid": uid, "gid": gid, "home": u.Home, "shell": shell}})
	case "network_interfaces":
		interfaces, err := net.Interfaces()
		if err != nil {
			return libraryOSResult(r, nil, err)
		}
		var items []Value
		for _, iface := range interfaces {
			CheckCancelled(ctx)
			if !utf8.ValidString(iface.Name) {
				return libraryError(r, "Unsupported", "")
			}
			addresses, err := iface.Addrs()
			if err != nil {
				return libraryOSResult(r, nil, err)
			}
			for _, a := range addresses {
				ip, network, err := net.ParseCIDR(a.String())
				if err != nil {
					continue
				}
				family := "IPv6"
				if ip.To4() != nil {
					family = "IPv4"
				}
				items = append(items, Record{"@std/NetworkInterface", map[string]Value{"name": iface.Name, "address": ip.String(), "netmask": net.IP(network.Mask).String(), "family": Alternative{"@std/IpFamily", family, nil}, "mac": iface.HardwareAddr.String(), "internal": iface.Flags&net.FlagLoopback != 0, "scope_id": int64(iface.Index)}})
			}
		}
		return libraryOK(r, libraryList("@std/NetworkInterface", items))
	case "machine":
		names := map[string]string{"amd64": "x86_64", "arm64": "aarch64", "386": "i686"}
		v := names[goruntime.GOARCH]
		if v == "" {
			v = goruntime.GOARCH
		}
		return libraryOK(r, v)
	case "os_release", "os_version":
		var v string
		var err error
		if name == "os_release" {
			v, err = hostos.OSRelease()
		} else {
			v, err = hostos.OSVersion()
		}
		return libraryUTF8Result(r, strings.TrimSpace(v), err)
	case "metrics":
		return librarySystemMetrics(ctx, r)
	case "cpus":
		return libraryCPUs(ctx, r)
	}
	return Panic("unknown system operation")
}

func librarySystemMetrics(ctx *Execution, r string) Value {
	memory, err := memstats.VirtualMemoryWithContext(ctx.Context)
	CheckCancelled(ctx)
	if err != nil {
		return libraryOSResult(r, nil, err)
	}
	uptime, err := hoststats.UptimeWithContext(ctx.Context)
	CheckCancelled(ctx)
	if err != nil {
		return libraryOSResult(r, nil, err)
	}
	loads := []Value{float64(0), float64(0), float64(0)}
	if goruntime.GOOS != "windows" {
		load, err := loadstats.AvgWithContext(ctx.Context)
		CheckCancelled(ctx)
		if err != nil {
			return libraryOSResult(r, nil, err)
		}
		loads = []Value{load.Load1, load.Load5, load.Load15}
	}
	parallelism, err := hostos.AvailableParallelism()
	if err != nil {
		return libraryOSResult(r, nil, err)
	}
	return libraryOK(r, Record{"@std/SystemMetrics", map[string]Value{"total_memory": int64(memory.Total), "free_memory": int64(memory.Free), "available_memory": int64(memory.Available), "uptime": Duration(time.Duration(uptime) * time.Second), "load_average": libraryList("Float", loads), "available_parallelism": int64(parallelism)}})
}
func libraryCPUs(ctx *Execution, r string) Value {
	infos, err := cpustats.InfoWithContext(ctx.Context)
	CheckCancelled(ctx)
	if err != nil {
		return libraryOSResult(r, nil, err)
	}
	times, err := cpustats.TimesWithContext(ctx.Context, true)
	CheckCancelled(ctx)
	if err != nil {
		return libraryOSResult(r, nil, err)
	}
	byID := map[int]cpustats.InfoStat{}
	for _, info := range infos {
		byID[int(info.CPU)] = info
	}
	items := make([]Value, 0, len(times))
	for i, usage := range times {
		info, ok := byID[i]
		if !ok && len(infos) > 0 {
			info = infos[0]
		}
		if !utf8.ValidString(info.ModelName) {
			return libraryError(r, "Unsupported", "")
		}
		items = append(items, Record{"@std/CpuInfo", map[string]Value{"model": info.ModelName, "speed_mhz": int64(info.Mhz), "user": int64(usage.User * 1000), "nice": int64(usage.Nice * 1000), "system": int64(usage.System * 1000), "idle": int64(usage.Idle * 1000), "irq": int64((usage.Irq + usage.Softirq) * 1000)}})
	}
	return libraryOK(r, libraryList("@std/CpuInfo", items))
}

type libraryProcessControl struct{}

func (libraryProcessControl) Operation(name string) Function {
	return libraryMethod("ProcessControl", name, func(ctx *Execution, r string, a []Value) Value {
		CheckCancelled(ctx)
		switch name {
		case "monotonic_time":
			return int64(time.Since(libraryProcessStarted))
		case "watch_signals":
			return libraryNewSignalStream(ctx, r, a)
		case "constrained_memory", "available_memory":
			limit, current, err := libraryMemoryLimit()
			if err != nil {
				return libraryOSResult(r, nil, err)
			}
			if name == "constrained_memory" {
				return libraryOK(r, limit)
			}
			metrics := librarySystemMetrics(ctx, r).(Alternative)
			if metrics.Tag != "ok" {
				return metrics
			}
			available := metrics.Fields[0].(Record).Fields["available_memory"].(int64)
			if limit > 0 {
				remaining := max(limit-current, 0)
				available = min(available, remaining)
			}
			return libraryOK(r, available)
		case "title", "set_title":
			if name == "title" {
				value, err := hostos.ProcessTitle()
				return libraryUTF8Result(r, value, err)
			}
			title := a[0].(string)
			if strings.ContainsAny(title, "\x00\n") {
				return libraryError(r, "InvalidInput", "")
			}
			return libraryOSResult(r, Unit{}, hostos.SetProcessTitle(title))
		case "initialize_groups":
			gid := a[1].(int64)
			username := a[0].(string)
			if gid < 0 || gid > 2147483647 || strings.ContainsRune(username, 0) {
				return libraryError(r, "InvalidInput", "")
			}
			u, err := user.Lookup(username)
			if err != nil {
				return libraryOSResult(r, nil, err)
			}
			names, err := u.GroupIds()
			if err != nil {
				return libraryOSResult(r, nil, err)
			}
			groups := []int{int(gid)}
			seen := map[int]bool{int(gid): true}
			for _, name := range names {
				id, err := strconv.ParseInt(name, 10, 32)
				if err != nil || id < 0 {
					return libraryError(r, "InvalidData", "")
				}
				if !seen[int(id)] {
					groups = append(groups, int(id))
					seen[int(id)] = true
				}
			}
			return libraryOSResult(r, Unit{}, hostos.SetGroups(groups))
		case "replace":
			program := a[0].(string)
			arguments := libraryStringValues(a[1])
			environment := []string{}
			if program == "" || strings.ContainsRune(program, 0) || len(arguments) == 0 {
				return libraryError(r, "InvalidInput", "")
			}
			for _, arg := range arguments {
				if strings.ContainsRune(arg, 0) {
					return libraryError(r, "InvalidInput", "")
				}
			}
			for _, entry := range a[2].(*Map).Entries {
				key, value := entry.Key.(string), entry.Value.(string)
				if key == "" || strings.ContainsAny(key, "=\x00") || strings.ContainsRune(value, 0) {
					return libraryError(r, "InvalidInput", "")
				}
				environment = append(environment, key+"="+value)
			}
			CheckCancelled(ctx)
			return libraryOSResult(r, Unit{}, hostos.Exec(program, arguments, environment))
		case "resource_usage":
			u, err := hostos.ResourceUsage()
			if err != nil {
				return libraryOSResult(r, nil, err)
			}
			return libraryOK(r, Record{"@std/ResourceUsage", map[string]Value{"user_microseconds": u.User, "system_microseconds": u.System, "max_resident_bytes": u.MaxRSS, "minor_faults": u.MinorFaults, "major_faults": u.MajorFaults, "filesystem_reads": u.Reads, "filesystem_writes": u.Writes, "voluntary_switches": u.VoluntarySwitches, "involuntary_switches": u.InvoluntarySwitches}})
		case "umask":
			mask := a[0].(int64)
			if mask < 0 || mask > 0777 {
				return libraryError(r, "InvalidInput", "")
			}
			libraryDirectoryMu.Lock()
			v := hostos.Umask(int(mask))
			libraryDirectoryMu.Unlock()
			if v < 0 {
				return libraryError(r, "Unsupported", "")
			}
			return libraryOK(r, int64(v))
		case "set_identity":
			kind := a[0].(string)
			id := a[1].(int64)
			if id < 0 || id > 2147483647 || (kind != "uid" && kind != "gid" && kind != "euid" && kind != "egid") {
				return libraryError(r, "InvalidInput", "")
			}
			return libraryOSResult(r, Unit{}, hostos.SetIdentity(kind, int(id)))
		case "set_groups":
			var groups []int
			for _, v := range a[0].(*List).Items {
				id := v.(int64)
				if id < 0 || id > 2147483647 {
					return libraryError(r, "InvalidInput", "")
				}
				groups = append(groups, int(id))
			}
			return libraryOSResult(r, Unit{}, hostos.SetGroups(groups))
		case "info":
			executable, err := os.Executable()
			if err != nil {
				return libraryOSResult(r, nil, err)
			}
			if !utf8.ValidString(executable + strings.Join(os.Args, "")) {
				return libraryError(r, "Unsupported", "")
			}
			return libraryOK(r, Record{"@std/ProcessInfo", map[string]Value{"pid": int64(os.Getpid()), "parent_pid": int64(os.Getppid()), "executable": executable, "arguments": libraryStrings(os.Args), "os": goruntime.GOOS, "architecture": goruntime.GOARCH, "uid": int64(os.Getuid()), "gid": int64(os.Getgid()), "effective_uid": int64(os.Geteuid()), "effective_gid": int64(os.Getegid())}})
		case "uptime":
			return libraryOK(r, Duration(time.Since(libraryProcessStarted)))
		case "memory_usage":
			var mem goruntime.MemStats
			goruntime.ReadMemStats(&mem)
			p, err := processstats.NewProcessWithContext(ctx.Context, int32(os.Getpid()))
			if err != nil {
				return libraryOSResult(r, nil, err)
			}
			memory, err := p.MemoryInfoWithContext(ctx.Context)
			CheckCancelled(ctx)
			if err != nil {
				return libraryOSResult(r, nil, err)
			}
			resident := int64(memory.RSS)
			return libraryOK(r, Record{"@std/MemoryUsage", map[string]Value{"heap_used": int64(mem.HeapAlloc), "heap_total": int64(mem.HeapInuse), "heap_system": int64(mem.HeapSys), "external": int64(mem.Sys - mem.HeapSys), "resident": resident}})
		case "cpu_usage":
			usage, err := hostos.ResourceUsage()
			if err != nil {
				return libraryOSResult(r, nil, err)
			}
			return libraryOK(r, Record{"@std/CpuUsage", map[string]Value{"user_microseconds": usage.User, "system_microseconds": usage.System}})
		case "environment":
			libraryEnvironmentMu.Lock()
			defer libraryEnvironmentMu.Unlock()
			env := &Map{Type: "@std/Map[String][String]"}
			for _, entry := range os.Environ() {
				if !utf8.ValidString(entry) {
					return libraryError(r, "Unsupported", "")
				}
				key, value, ok := strings.Cut(entry, "=")
				if ok {
					env.Entries = append(env.Entries, Entry{key, value})
				}
			}
			return libraryOK(r, env)
		case "set_environment":
			key := a[0].(string)
			if key == "" || strings.ContainsAny(key, "=\x00") {
				return libraryError(r, "InvalidInput", "")
			}
			value := a[1].(Alternative)
			libraryEnvironmentMu.Lock()
			defer libraryEnvironmentMu.Unlock()
			var err error
			if value.Tag == "some" {
				text := value.Fields[0].(string)
				if strings.ContainsRune(text, 0) {
					return libraryError(r, "InvalidInput", "")
				}
				err = os.Setenv(key, text)
			} else {
				err = os.Unsetenv(key)
			}
			return libraryOSResult(r, Unit{}, err)
		case "load_environment":
			max := a[1].(int64)
			if max < 0 || strings.ContainsRune(a[0].(string), 0) {
				return libraryError(r, "InvalidInput", "")
			}
			file, err := os.Open(a[0].(string))
			if err != nil {
				return libraryOSResult(r, nil, err)
			}
			defer file.Close()
			data, code := libraryReadBounded(ctx, file, max)
			if code != "" {
				return libraryError(r, code, "")
			}
			if !utf8.Valid(data) {
				return libraryError(r, "InvalidData", "")
			}
			entries, ok := libraryParseEnvironment(string(data))
			if !ok {
				return libraryError(r, "InvalidData", "")
			}
			libraryEnvironmentMu.Lock()
			defer libraryEnvironmentMu.Unlock()
			for _, e := range entries {
				if _, exists := os.LookupEnv(e.Key.(string)); !exists {
					if err := os.Setenv(e.Key.(string), e.Value.(string)); err != nil {
						return libraryOSResult(r, nil, err)
					}
				}
			}
			return libraryOK(r, Unit{})
		case "working_directory":
			libraryDirectoryMu.Lock()
			defer libraryDirectoryMu.Unlock()
			v, err := os.Getwd()
			return libraryUTF8Result(r, v, err)
		case "change_directory":
			p := a[0].(string)
			if strings.ContainsRune(p, 0) {
				return libraryError(r, "InvalidInput", "")
			}
			libraryDirectoryMu.Lock()
			defer libraryDirectoryMu.Unlock()
			return libraryOSResult(r, Unit{}, os.Chdir(p))
		case "send_signal":
			pid, signal := a[0].(int64), a[1].(int64)
			if pid < -2147483648 || pid > 2147483647 || signal < 0 || signal > 64 {
				return libraryError(r, "InvalidInput", "")
			}
			return libraryOSResult(r, Unit{}, hostos.SendSignal(int(pid), int(signal)))
		case "groups":
			if goruntime.GOOS == "windows" {
				return libraryError(r, "Unsupported", "")
			}
			groups, err := os.Getgroups()
			if err != nil {
				return libraryOSResult(r, nil, err)
			}
			items := make([]Value, len(groups))
			for i, g := range groups {
				items[i] = int64(g)
			}
			return libraryOK(r, libraryList("Int", items))
		}
		return Panic("unknown process operation")
	})
}

// Parse fully before mutating the environment. Existing variables win. Quoted
// values can span lines; comments outside quotes and an export prefix are accepted.
func libraryParseEnvironment(text string) ([]Entry, bool) {
	text = strings.TrimPrefix(text, "\ufeff")
	var entries []Entry
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
		entries = append(entries, Entry{key, value})
	}
	return entries, true
}

// Resolve the process's own cgroup path; do not substitute the cgroup mount root
// when the process is in a nested group. v1 and v2 are both supported.
func libraryMemoryLimit() (int64, int64, error) {
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
		return limit, current, nil
	}
	return 0, 0, nil
}
