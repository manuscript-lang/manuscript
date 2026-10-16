package msruntime

import (
	"net"
	"os"
	goruntime "runtime"
	"strings"
	"unicode/utf8"

	"github.com/manuscript-lang/manuscript/internal/hostos"
	cpustats "github.com/shirou/gopsutil/v4/cpu"
	hoststats "github.com/shirou/gopsutil/v4/host"
	loadstats "github.com/shirou/gopsutil/v4/load"
	memstats "github.com/shirou/gopsutil/v4/mem"
)

// System_OsType is the operating system name in uname style.
func System_OsType(*Execution) string {
	names := map[string]string{"linux": "Linux", "darwin": "Darwin", "windows": "Windows_NT"}
	if name := names[goruntime.GOOS]; name != "" {
		return name
	}
	return goruntime.GOOS
}

// System_Constants is the table of host signal and priority constants.
func System_Constants(*Execution) *Map[string, int] { return constantsMap(hostos.Constants()) }

// System_DevNull is the null device path.
func System_DevNull(*Execution) string { return os.DevNull }

// System_EndOfLine is the platform line ending.
func System_EndOfLine(*Execution) string {
	if goruntime.GOOS == "windows" {
		return "\r\n"
	}
	return "\n"
}

// System_Endianness is "LE" or "BE".
func System_Endianness(*Execution) string {
	switch goruntime.GOARCH {
	case "s390x", "ppc64", "mips", "mips64":
		return "BE"
	}
	return "LE"
}

func sysErrorOf(err error) SystemError {
	switch classifyOS(err, false) {
	case kindInvalidInput:
		return SystemError_InvalidInput{}
	case kindUnsupported:
		return SystemError_Unsupported{}
	case kindNotFound:
		return SystemError_NotFound{}
	case kindAlreadyExists:
		return SystemError_AlreadyExists{}
	case kindPermissionDenied:
		return SystemError_PermissionDenied{}
	}
	return SystemError_Failed{Message: err.Error()}
}

func sysFail[T any](e SystemError) Result[T, SystemError] { return Fail[T, SystemError](e) }

func sysDone[T any](value T, err error) Result[T, SystemError] {
	if err != nil {
		return sysFail[T](sysErrorOf(err))
	}
	return Ok[T, SystemError](value)
}

// sysText is sysDone for text that must be UTF-8.
func sysText(s string, err error) Result[string, SystemError] {
	if err == nil && !utf8.ValidString(s) {
		return sysFail[string](SystemError_Unsupported{})
	}
	return sysDone(s, err)
}

// osSystem is the host system service. A nonempty directory pins the working
// directory it reports.
type osSystem struct{ directory string }

var _ System = (*osSystem)(nil)

func (s *osSystem) Environment(_ *Execution, name string) Option[string] {
	v, ok := os.LookupEnv(name)
	if !utf8.ValidString(v) {
		ok = false
	}
	return Option[string]{Val: v, Some: ok}
}

func (s *osSystem) Info(*Execution) *SystemInfo {
	return &SystemInfo{Os: goruntime.GOOS, Architecture: goruntime.GOARCH, CpuCount: int(goruntime.NumCPU())}
}

func (s *osSystem) WorkingDirectory(*Execution) string {
	if s.directory != "" {
		return s.directory
	}
	workingDirectoryMu.Lock()
	defer workingDirectoryMu.Unlock()
	directory, err := os.Getwd()
	if err != nil {
		Raise(err.Error())
	}
	return directory
}

func (s *osSystem) Hostname(ctx *Execution) Result[string, SystemError] {
	CheckCancelled(ctx)
	v, err := os.Hostname()
	return sysText(v, err)
}

func (s *osSystem) HomeDirectory(ctx *Execution) Result[string, SystemError] {
	CheckCancelled(ctx)
	v, err := os.UserHomeDir()
	return sysText(v, err)
}

func (s *osSystem) TemporaryDirectory(ctx *Execution) Result[string, SystemError] {
	CheckCancelled(ctx)
	return sysText(os.TempDir(), nil)
}

func (s *osSystem) UserInfo(ctx *Execution) Result[*UserInfo, SystemError] {
	CheckCancelled(ctx)
	u, err := hostos.CurrentUser()
	if err != nil {
		return sysDone[*UserInfo](nil, err)
	}
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
		return sysFail[*UserInfo](SystemError_Unsupported{})
	}
	return Ok[*UserInfo, SystemError](&UserInfo{Username: u.Username, Uid: FitInt(u.UID), Gid: FitInt(u.GID), Home: u.Home, Shell: shell})
}

func (s *osSystem) NetworkInterfaces(ctx *Execution) Result[*List[*NetworkInterface], SystemError] {
	CheckCancelled(ctx)
	interfaces, err := net.Interfaces()
	if err != nil {
		return sysDone[*List[*NetworkInterface]](nil, err)
	}
	var items []*NetworkInterface
	for _, iface := range interfaces {
		CheckCancelled(ctx)
		if !utf8.ValidString(iface.Name) {
			return sysFail[*List[*NetworkInterface]](SystemError_Unsupported{})
		}
		addresses, err := iface.Addrs()
		if err != nil {
			return sysDone[*List[*NetworkInterface]](nil, err)
		}
		for _, a := range addresses {
			ip, network, err := net.ParseCIDR(a.String())
			if err != nil {
				continue
			}
			var family IpFamily = IpFamily_IPv6{}
			if ip.To4() != nil {
				family = IpFamily_IPv4{}
			}
			items = append(items, &NetworkInterface{Name: iface.Name, Address: ip.String(), Netmask: net.IP(network.Mask).String(), Family: family, Mac: iface.HardwareAddr.String(), Internal: iface.Flags&net.FlagLoopback != 0, ScopeId: int(iface.Index)})
		}
	}
	return Ok[*List[*NetworkInterface], SystemError](NewList(items...))
}

func (s *osSystem) Cpus(ctx *Execution) Result[*List[*CpuInfo], SystemError] {
	infos, err := cpustats.InfoWithContext(ctx.Context)
	CheckCancelled(ctx)
	if err != nil {
		return sysDone[*List[*CpuInfo]](nil, err)
	}
	times, err := cpustats.TimesWithContext(ctx.Context, true)
	CheckCancelled(ctx)
	if err != nil {
		return sysDone[*List[*CpuInfo]](nil, err)
	}
	byID := map[int]cpustats.InfoStat{}
	for _, info := range infos {
		byID[int(info.CPU)] = info
	}
	items := make([]*CpuInfo, 0, len(times))
	for i, usage := range times {
		info, ok := byID[i]
		if !ok && len(infos) > 0 {
			info = infos[0]
		}
		if !utf8.ValidString(info.ModelName) {
			return sysFail[*List[*CpuInfo]](SystemError_Unsupported{})
		}
		items = append(items, &CpuInfo{Model: info.ModelName, SpeedMhz: int(info.Mhz), User: int(usage.User * 1000), Nice: int(usage.Nice * 1000), System: int(usage.System * 1000), Idle: int(usage.Idle * 1000), Irq: int((usage.Irq + usage.Softirq) * 1000)})
	}
	return Ok[*List[*CpuInfo], SystemError](NewList(items...))
}

func (s *osSystem) Metrics(ctx *Execution) Result[*SystemMetrics, SystemError] {
	memory, err := memstats.VirtualMemoryWithContext(ctx.Context)
	CheckCancelled(ctx)
	if err != nil {
		return sysDone[*SystemMetrics](nil, err)
	}
	uptime, err := hoststats.UptimeWithContext(ctx.Context)
	CheckCancelled(ctx)
	if err != nil {
		return sysDone[*SystemMetrics](nil, err)
	}
	loads := []float64{0, 0, 0}
	if goruntime.GOOS != "windows" {
		load, err := loadstats.AvgWithContext(ctx.Context)
		CheckCancelled(ctx)
		if err != nil {
			return sysDone[*SystemMetrics](nil, err)
		}
		loads = []float64{load.Load1, load.Load5, load.Load15}
	}
	parallelism, err := hostos.AvailableParallelism()
	if err != nil {
		return sysDone[*SystemMetrics](nil, err)
	}
	return Ok[*SystemMetrics, SystemError](&SystemMetrics{TotalMemory: int(memory.Total), FreeMemory: int(memory.Free), AvailableMemory: int(memory.Available), Uptime: Duration(uptime) * Duration(1e9), LoadAverage: NewList(loads...), AvailableParallelism: int(parallelism)})
}

func (s *osSystem) OsRelease(ctx *Execution) Result[string, SystemError] {
	CheckCancelled(ctx)
	v, err := hostos.OSRelease()
	return sysText(strings.TrimSpace(v), err)
}

func (s *osSystem) OsVersion(ctx *Execution) Result[string, SystemError] {
	CheckCancelled(ctx)
	v, err := hostos.OSVersion()
	return sysText(strings.TrimSpace(v), err)
}

func (s *osSystem) Machine(ctx *Execution) Result[string, SystemError] {
	CheckCancelled(ctx)
	names := map[string]string{"amd64": "x86_64", "arm64": "aarch64", "386": "i686"}
	v := names[goruntime.GOARCH]
	if v == "" {
		v = goruntime.GOARCH
	}
	return Ok[string, SystemError](v)
}

func (s *osSystem) GetPriority(ctx *Execution, pid int) Result[int, SystemError] {
	CheckCancelled(ctx)
	if pid < 0 || pid > 2147483647 {
		return sysFail[int](SystemError_InvalidInput{})
	}
	v, err := hostos.GetPriority(int(pid))
	return sysDone(int(v), err)
}

func (s *osSystem) SetPriority(ctx *Execution, pid, priority int) Result[Unit, SystemError] {
	CheckCancelled(ctx)
	if pid < 0 || pid > 2147483647 || priority < -20 || priority > 19 {
		return sysFail[Unit](SystemError_InvalidInput{})
	}
	return sysDone(Unit{}, hostos.SetPriority(int(pid), int(priority)))
}
