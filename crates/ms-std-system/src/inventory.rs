//! Host inventories behind `System.network_interfaces`, `cpus` and `metrics`.
//!
//! Each call takes a snapshot that `lib.rs` hands out as one record, or a list of them.
//! Network interfaces work on every unix host. `cpus` reads `/proc` on Linux, the Mach
//! host on macOS and `NtQuerySystemInformation` on Windows; `metrics` reads `sysinfo` on
//! Linux, the Mach host statistics on macOS and `GlobalMemoryStatusEx` on Windows.
#![allow(unsafe_code)] // libc `getifaddrs` and friends

use alloc::vec::Vec;
use ms_rt::ffi::Failure;
use ms_rt_abi::STATUS_UNSUPPORTED;
#[cfg(any(target_os = "linux", target_os = "android"))]
use ms_rt_abi::{STATUS_NOT_FOUND, STATUS_PERMISSION_DENIED};

/// One address of one network interface.
#[derive(Default)]
pub struct Interface {
    pub name: Vec<u8>,
    pub address: Vec<u8>,
    pub netmask: Vec<u8>,
    pub v6: bool,
    pub mac: Vec<u8>,
    pub internal: bool,
    pub scope_id: i64,
}

/// One logical CPU; times are cumulative milliseconds.
#[derive(Clone, Default)]
pub struct Cpu {
    pub model: Vec<u8>,
    pub speed_mhz: i64,
    pub user: i64,
    pub nice: i64,
    pub system: i64,
    pub idle: i64,
    pub irq: i64,
}

#[derive(Default)]
pub struct Metrics {
    pub total_memory: i64,
    pub free_memory: i64,
    pub available_memory: i64,
    pub uptime_ns: i64,
    pub load: [f64; 3],
    pub parallelism: i64,
}

#[cfg(unix)]
pub fn interfaces() -> Result<Vec<Interface>, Failure> {
    use core::ffi::CStr;

    let mut head: *mut libc::ifaddrs = core::ptr::null_mut();
    // SAFETY: `head` receives a list that `freeifaddrs` releases below.
    if unsafe { libc::getifaddrs(&mut head) } != 0 {
        return Err(Failure::failed("getifaddrs failed"));
    }
    let mut macs: Vec<(Vec<u8>, Vec<u8>)> = Vec::new();
    let mut found = Vec::new();
    let mut result: Result<(), Failure> = Ok(());
    let mut at = head;
    while !at.is_null() {
        // SAFETY: the list nodes stay valid until `freeifaddrs`.
        let ifa = unsafe { &*at };
        at = ifa.ifa_next;
        if ifa.ifa_addr.is_null() {
            continue;
        }
        // SAFETY: `ifa_name` is a NUL-terminated string.
        let name = unsafe { CStr::from_ptr(ifa.ifa_name) }.to_bytes().to_vec();
        if core::str::from_utf8(&name).is_err() {
            result = Err(STATUS_UNSUPPORTED.into());
            break;
        }
        // SAFETY: a non-null `ifa_addr` points at a sockaddr.
        let family = i32::from(unsafe { (*ifa.ifa_addr).sa_family });
        #[cfg(any(target_os = "linux", target_os = "android"))]
        if family == libc::AF_PACKET {
            // SAFETY: AF_PACKET addresses are `sockaddr_ll`.
            let ll = unsafe { &*(ifa.ifa_addr as *const libc::sockaddr_ll) };
            let len = usize::from(ll.sll_halen).min(ll.sll_addr.len());
            // Interfaces without a hardware address (loopback) report all zeros.
            if ll.sll_addr[..len].iter().any(|&b| b != 0) {
                macs.push((name, hex_mac(&ll.sll_addr[..len])));
            }
            continue;
        }
        let v6 = match family {
            libc::AF_INET => false,
            libc::AF_INET6 => true,
            _ => continue,
        };
        if ifa.ifa_netmask.is_null() {
            continue;
        }
        let (Some(address), Some(netmask)) =
            (ip_text(ifa.ifa_addr, v6), ip_text(ifa.ifa_netmask, v6))
        else {
            continue;
        };
        found.push(Interface {
            // SAFETY: `ifa_name` is a NUL-terminated string.
            scope_id: i64::from(unsafe { libc::if_nametoindex(ifa.ifa_name) }),
            name,
            address,
            netmask,
            v6,
            mac: Vec::new(),
            internal: ifa.ifa_flags & libc::IFF_LOOPBACK as u32 != 0,
        });
    }
    // SAFETY: `head` came from `getifaddrs` and nothing borrows it any more.
    unsafe { libc::freeifaddrs(head) };
    result?;
    for item in &mut found {
        if let Some((_, mac)) = macs.iter().find(|(n, _)| *n == item.name) {
            item.mac = mac.clone();
        }
    }
    // The kernel's interface order, like `net.Interfaces`; the sort is stable.
    found.sort_by_key(|i| i.scope_id);
    Ok(found)
}

#[cfg(unix)]
fn ip_text(sa: *const libc::sockaddr, v6: bool) -> Option<Vec<u8>> {
    use alloc::string::ToString;
    use core::net::{Ipv4Addr, Ipv6Addr};

    let text = if v6 {
        // SAFETY: an AF_INET6 sockaddr is a `sockaddr_in6`.
        let a = unsafe { &*(sa as *const libc::sockaddr_in6) };
        Ipv6Addr::from(a.sin6_addr.s6_addr).to_string()
    } else {
        // SAFETY: an AF_INET sockaddr is a `sockaddr_in`.
        let a = unsafe { &*(sa as *const libc::sockaddr_in) };
        // `s_addr` is in network byte order, so its native bytes are the address octets.
        Ipv4Addr::from(a.sin_addr.s_addr.to_ne_bytes()).to_string()
    };
    Some(text.into_bytes())
}

#[cfg(any(target_os = "linux", target_os = "android"))]
fn hex_mac(bytes: &[u8]) -> Vec<u8> {
    const DIGITS: &[u8; 16] = b"0123456789abcdef";
    let mut out = Vec::with_capacity(bytes.len() * 3);
    for (i, b) in bytes.iter().enumerate() {
        if i > 0 {
            out.push(b':');
        }
        out.push(DIGITS[usize::from(b >> 4)]);
        out.push(DIGITS[usize::from(b & 15)]);
    }
    out
}

#[cfg(not(unix))]
pub fn interfaces() -> Result<Vec<Interface>, Failure> {
    Err(STATUS_UNSUPPORTED.into())
}

/// The whole of `path`; `/proc` files report no size, so it reads until the end.
#[cfg(any(target_os = "linux", target_os = "android"))]
fn read_file(path: &str) -> Result<Vec<u8>, Failure> {
    use std::io::ErrorKind;

    std::fs::read(path).map_err(|e| match e.kind() {
        ErrorKind::NotFound => STATUS_NOT_FOUND.into(),
        ErrorKind::PermissionDenied => STATUS_PERMISSION_DENIED.into(),
        _ => Failure::failed("cannot read host statistics"),
    })
}

#[cfg(any(target_os = "linux", target_os = "android"))]
fn number(bytes: &[u8]) -> i64 {
    let digits = bytes.iter().take_while(|b| b.is_ascii_digit());
    digits.fold(0i64, |n, &b| {
        n.saturating_mul(10).saturating_add(i64::from(b - b'0'))
    })
}

/// The value after `key:` on a `/proc` line, without surrounding blanks.
#[cfg(any(target_os = "linux", target_os = "android"))]
fn field<'a>(line: &'a [u8], key: &[u8]) -> Option<&'a [u8]> {
    let rest = line
        .strip_prefix(key)?
        .trim_ascii_start()
        .strip_prefix(b":")?;
    Some(rest.trim_ascii())
}

#[cfg(any(target_os = "linux", target_os = "android"))]
pub fn cpus() -> Result<Vec<Cpu>, Failure> {
    let stat = read_file("/proc/stat")?;
    let info = read_file("/proc/cpuinfo").unwrap_or_default();
    // (model, MHz) of each `processor` block.
    let mut models: Vec<(Vec<u8>, i64)> = Vec::new();
    for line in info.split(|&b| b == b'\n') {
        if field(line, b"processor").is_some() {
            models.push((Vec::new(), 0));
        } else if let Some(last) = models.last_mut() {
            if let Some(v) = field(line, b"model name") {
                last.0 = v.to_vec();
            } else if let Some(v) = field(line, b"cpu MHz") {
                last.1 = number(v);
            }
        }
    }
    let ticks = i64::try_from(rustix::param::clock_ticks_per_second())
        .unwrap_or(i64::MAX)
        .max(1);
    let ms = |jiffies: i64| jiffies.saturating_mul(1000) / ticks;
    let mut cpus: Vec<Cpu> = Vec::new();
    for line in stat.split(|&b| b == b'\n') {
        let Some(rest) = line.strip_prefix(b"cpu") else {
            continue;
        };
        // The aggregate `cpu ` line has no index.
        if !rest.first().is_some_and(u8::is_ascii_digit) {
            continue;
        }
        let mut parts = line.split(|&b| b == b' ').filter(|p| !p.is_empty()).skip(1);
        let mut next = || parts.next().map_or(0, number);
        let (user, nice, system, idle) = (next(), next(), next(), next());
        let (_iowait, irq, softirq) = (next(), next(), next());
        let (model, speed_mhz) = models
            .get(cpus.len())
            .or_else(|| models.first())
            .cloned()
            .unwrap_or_default();
        cpus.push(Cpu {
            model,
            speed_mhz,
            user: ms(user),
            nice: ms(nice),
            system: ms(system),
            idle: ms(idle),
            irq: ms(irq + softirq),
        });
    }
    Ok(cpus)
}

#[cfg(any(target_os = "linux", target_os = "android"))]
#[allow(clippy::useless_conversion)] // `sysinfo` fields are narrower than 64 bits on 32-bit hosts
pub fn metrics() -> Result<Metrics, Failure> {
    let info = rustix::system::sysinfo();
    let unit = u64::from(info.mem_unit.max(1));
    let bytes = |n: u64| i64::try_from(n.saturating_mul(unit)).unwrap_or(i64::MAX);
    let free = bytes(info.freeram.into());
    // `sysinfo` has no available-memory figure; kernels before 3.14 lack `MemAvailable` too,
    // and free memory is the honest lower bound.
    let available = read_file("/proc/meminfo")
        .ok()
        .and_then(|mem| {
            mem.split(|&b| b == b'\n')
                .find_map(|l| field(l, b"MemAvailable"))
                .map(number)
        })
        .map_or(0, |kib| kib.saturating_mul(1024));
    // Load averages are fixed-point with 16 fractional bits.
    let load = info.loads.map(|l| l as f64 / 65536.0);
    Ok(Metrics {
        total_memory: bytes(info.totalram.into()),
        free_memory: free,
        available_memory: if available == 0 { free } else { available },
        uptime_ns: i64::from(info.uptime).saturating_mul(1_000_000_000),
        load,
        parallelism: parallelism(),
    })
}

/// Logical processors this process may run on.
#[cfg(any(target_os = "linux", target_os = "android"))]
fn parallelism() -> i64 {
    match rustix::thread::sched_getaffinity(None) {
        Ok(set) => i64::from(set.count()).max(1),
        Err(_) => crate::imp::cpu_count(),
    }
}

/// One CPU per logical processor from the Mach host: the cumulative ticks of each state,
/// the brand string, and the clock in MHz where the kernel reports it (Apple silicon does
/// not, so it reads 0). The kernel keeps no interrupt time, so `irq` is 0.
#[cfg(target_os = "macos")]
pub fn cpus() -> Result<Vec<Cpu>, Failure> {
    let mut count: libc::natural_t = 0;
    let mut info: libc::processor_info_array_t = core::ptr::null_mut();
    let mut info_len: libc::mach_msg_type_number_t = 0;
    // SAFETY: the three out parameters are writable and the host port is the caller's own.
    let rc = unsafe {
        libc::host_processor_info(
            libc::mach_host_self(),
            libc::PROCESSOR_CPU_LOAD_INFO,
            &mut count,
            &mut info,
            &mut info_len,
        )
    };
    if rc != libc::KERN_SUCCESS || info.is_null() {
        return Err(Failure::failed("cannot read host statistics"));
    }
    // SAFETY: plain system call.
    let hz = unsafe { libc::sysconf(libc::_SC_CLK_TCK) }.max(1);
    let ms = |ticks: libc::c_int| i64::from(ticks as u32).saturating_mul(1000) / hz;
    let model = sysctl_bytes(c"machdep.cpu.brand_string").unwrap_or_default();
    let speed_mhz = sysctl_u64(c"hw.cpufrequency")
        .map_or(0, |hz| i64::try_from(hz / 1_000_000).unwrap_or(i64::MAX));
    // SAFETY: on success the kernel returned `count` records of `cpu_ticks` integers.
    let loads = unsafe {
        core::slice::from_raw_parts(info.cast::<libc::processor_cpu_load_info>(), count as usize)
    };
    let all = loads
        .iter()
        .map(|load| {
            let ticks = |state: libc::c_int| ms(load.cpu_ticks[state as usize] as libc::c_int);
            Cpu {
                model: model.clone(),
                speed_mhz,
                user: ticks(libc::CPU_STATE_USER),
                nice: ticks(libc::CPU_STATE_NICE),
                system: ticks(libc::CPU_STATE_SYSTEM),
                idle: ticks(libc::CPU_STATE_IDLE),
                irq: 0,
            }
        })
        .collect();
    // SAFETY: the kernel allocated `info` in this task for the call above; it is released once.
    unsafe {
        libc::vm_deallocate(
            libc::mach_task_self(),
            info as libc::vm_address_t,
            info_len as libc::vm_size_t * core::mem::size_of::<libc::c_int>(),
        );
    }
    Ok(all)
}

/// One CPU per logical processor from `NtQuerySystemInformation`, whose counters are in
/// 100 ns units; kernel time includes idle time, so system time is the difference. The
/// model and clock come from the registry's processor keys. Only the current processor
/// group is reported.
#[cfg(windows)]
pub fn cpus() -> Result<Vec<Cpu>, Failure> {
    /// `SYSTEM_PROCESSOR_PERFORMANCE_INFORMATION`.
    #[repr(C)]
    #[derive(Default, Clone, Copy)]
    struct Performance {
        idle: i64,
        kernel: i64,
        user: i64,
        dpc: i64,
        interrupt: i64,
        interrupt_count: u32,
    }
    #[link(name = "ntdll", kind = "raw-dylib")]
    unsafe extern "system" {
        fn NtQuerySystemInformation(
            class: u32,
            buffer: *mut core::ffi::c_void,
            length: u32,
            returned: *mut u32,
        ) -> i32;
    }
    #[link(name = "advapi32", kind = "raw-dylib")]
    unsafe extern "system" {
        fn RegGetValueA(
            key: isize,
            sub_key: *const u8,
            value: *const u8,
            flags: u32,
            kind: *mut u32,
            data: *mut core::ffi::c_void,
            size: *mut u32,
        ) -> i32;
    }
    #[link(name = "kernel32", kind = "raw-dylib")]
    unsafe extern "system" {
        fn GetActiveProcessorCount(group: u16) -> u32;
    }
    const SYSTEM_PROCESSOR_PERFORMANCE_INFORMATION: u32 = 8;
    const HKEY_LOCAL_MACHINE: isize = 0x8000_0002_u32 as i32 as isize;
    const RRF_RT_REG_SZ: u32 = 0x2;
    const RRF_RT_REG_DWORD: u32 = 0x10;
    // The current group is all the call reports; ask for room for every group's processors.
    // SAFETY: a kernel32 call that only reads its argument.
    let room = unsafe { GetActiveProcessorCount(0xFFFF) }.max(1) as usize;
    let mut rows = alloc::vec![Performance::default(); room];
    let mut returned = 0u32;
    let bytes = u32::try_from(rows.len() * core::mem::size_of::<Performance>()).unwrap_or(u32::MAX);
    // SAFETY: `rows` is writable for `bytes` bytes and `returned` is writable.
    let status = unsafe {
        NtQuerySystemInformation(
            SYSTEM_PROCESSOR_PERFORMANCE_INFORMATION,
            rows.as_mut_ptr().cast(),
            bytes,
            &mut returned,
        )
    };
    if status < 0 {
        return Err(Failure::failed("cannot read host statistics"));
    }
    rows.truncate(returned as usize / core::mem::size_of::<Performance>());
    let ms = |units: i64| units.max(0) / 10_000;
    let all = rows
        .iter()
        .enumerate()
        .map(|(index, row)| {
            let key = alloc::format!("HARDWARE\\DESCRIPTION\\System\\CentralProcessor\\{index}\0");
            let mut name = [0u8; 256];
            let mut size = name.len() as u32;
            // SAFETY: the key and value names are NUL-terminated and `name` is writable for `size` bytes.
            let named = unsafe {
                RegGetValueA(
                    HKEY_LOCAL_MACHINE,
                    key.as_ptr(),
                    c"ProcessorNameString".as_ptr().cast(),
                    RRF_RT_REG_SZ,
                    core::ptr::null_mut(),
                    name.as_mut_ptr().cast(),
                    &mut size,
                )
            };
            let model = if named == 0 {
                let text = &name[..(size as usize).min(name.len())];
                text.split(|&b| b == 0)
                    .next()
                    .unwrap_or_default()
                    .trim_ascii()
                    .to_vec()
            } else {
                Vec::new()
            };
            let mut mhz = 0u32;
            let mut size = core::mem::size_of::<u32>() as u32;
            // SAFETY: `mhz` is writable for `size` bytes.
            let read = unsafe {
                RegGetValueA(
                    HKEY_LOCAL_MACHINE,
                    key.as_ptr(),
                    c"~MHz".as_ptr().cast(),
                    RRF_RT_REG_DWORD,
                    core::ptr::null_mut(),
                    (&raw mut mhz).cast(),
                    &mut size,
                )
            };
            Cpu {
                model,
                speed_mhz: if read == 0 { i64::from(mhz) } else { 0 },
                user: ms(row.user),
                nice: 0,
                system: ms(row.kernel - row.idle),
                idle: ms(row.idle),
                irq: ms(row.interrupt),
            }
        })
        .collect();
    Ok(all)
}

#[cfg(not(any(
    target_os = "linux",
    target_os = "android",
    target_os = "macos",
    windows
)))]
pub fn cpus() -> Result<Vec<Cpu>, Failure> {
    Err(STATUS_UNSUPPORTED.into())
}

/// A string sysctl value by name, without its trailing NUL.
#[cfg(target_os = "macos")]
fn sysctl_bytes(name: &core::ffi::CStr) -> Result<Vec<u8>, Failure> {
    let mut len = 0usize;
    // SAFETY: a null buffer asks for the size only.
    let rc = unsafe {
        libc::sysctlbyname(
            name.as_ptr(),
            core::ptr::null_mut(),
            &mut len,
            core::ptr::null_mut(),
            0,
        )
    };
    if rc != 0 {
        return Err(Failure::failed("cannot read host statistics"));
    }
    let mut buffer = alloc::vec![0u8; len];
    // SAFETY: `buffer` is writable for `len` bytes and `name` is NUL-terminated.
    let rc = unsafe {
        libc::sysctlbyname(
            name.as_ptr(),
            buffer.as_mut_ptr().cast(),
            &mut len,
            core::ptr::null_mut(),
            0,
        )
    };
    if rc != 0 {
        return Err(Failure::failed("cannot read host statistics"));
    }
    buffer.truncate(len);
    while buffer.last() == Some(&0) {
        buffer.pop();
    }
    Ok(buffer)
}

/// A `u64` sysctl value by name.
#[cfg(target_os = "macos")]
fn sysctl_u64(name: &core::ffi::CStr) -> Result<u64, Failure> {
    let mut value = 0u64;
    let mut len = core::mem::size_of::<u64>();
    // SAFETY: `value` is writable for `len` bytes and `name` is NUL-terminated.
    let rc = unsafe {
        libc::sysctlbyname(
            name.as_ptr(),
            (&raw mut value).cast(),
            &mut len,
            core::ptr::null_mut(),
            0,
        )
    };
    if rc == 0 && len == core::mem::size_of::<u64>() {
        Ok(value)
    } else {
        Err(Failure::failed("cannot read host statistics"))
    }
}

/// Memory from the Mach host statistics, uptime from the boot time, and the load averages
/// from `getloadavg`. Free memory is what the VM reports free; available adds the inactive
/// pages the kernel gives back on demand.
#[cfg(target_os = "macos")]
pub fn metrics() -> Result<Metrics, Failure> {
    let total = sysctl_u64(c"hw.memsize")?;
    let mut stats: libc::vm_statistics64 = unsafe { core::mem::zeroed() };
    let mut count = libc::HOST_VM_INFO64_COUNT;
    // SAFETY: `stats` is writable for `count` integers and the host port is the caller's own.
    let rc = unsafe {
        libc::host_statistics64(
            libc::mach_host_self(),
            libc::HOST_VM_INFO64,
            (&raw mut stats).cast(),
            &mut count,
        )
    };
    if rc != libc::KERN_SUCCESS {
        return Err(Failure::failed("cannot read host statistics"));
    }
    // SAFETY: plain system call.
    let page = u64::try_from(unsafe { libc::sysconf(libc::_SC_PAGESIZE) }).unwrap_or(4096);
    let bytes = |pages: u32| i64::try_from(u64::from(pages) * page).unwrap_or(i64::MAX);
    let total = i64::try_from(total).unwrap_or(i64::MAX);
    let free = bytes(stats.free_count.saturating_sub(stats.speculative_count));
    let available = bytes(stats.free_count.saturating_add(stats.inactive_count));
    let mut boot: libc::timeval = unsafe { core::mem::zeroed() };
    let mut len = core::mem::size_of::<libc::timeval>();
    // SAFETY: `boot` is writable for `len` bytes and the name is NUL-terminated.
    let rc = unsafe {
        libc::sysctlbyname(
            c"kern.boottime".as_ptr(),
            (&raw mut boot).cast(),
            &mut len,
            core::ptr::null_mut(),
            0,
        )
    };
    if rc != 0 {
        return Err(Failure::failed("cannot read host statistics"));
    }
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map_or(0, |d| i64::try_from(d.as_secs()).unwrap_or(i64::MAX));
    let uptime = now.saturating_sub(i64::from(boot.tv_sec)).max(0);
    let mut load = [0.0f64; 3];
    // SAFETY: `load` holds the three samples requested.
    if unsafe { libc::getloadavg(load.as_mut_ptr(), 3) } != 3 {
        load = [0.0; 3];
    }
    Ok(Metrics {
        total_memory: total,
        free_memory: free.min(total),
        available_memory: available.min(total).max(free.min(total)),
        uptime_ns: uptime.saturating_mul(1_000_000_000),
        load,
        parallelism: crate::imp::cpu_count(),
    })
}

/// Memory from `GlobalMemoryStatusEx` and uptime from `GetTickCount64`; Windows has no load
/// average, so the three figures are zero. The OS counts cached pages as available, so free
/// and available memory are the same figure.
#[cfg(windows)]
pub fn metrics() -> Result<Metrics, Failure> {
    #[repr(C)]
    struct MemoryStatusEx {
        length: u32,
        memory_load: u32,
        total_phys: u64,
        avail_phys: u64,
        total_page_file: u64,
        avail_page_file: u64,
        total_virtual: u64,
        avail_virtual: u64,
        avail_extended_virtual: u64,
    }
    unsafe extern "system" {
        fn GlobalMemoryStatusEx(buffer: *mut MemoryStatusEx) -> i32;
        fn GetTickCount64() -> u64;
    }
    let mut status = MemoryStatusEx {
        length: core::mem::size_of::<MemoryStatusEx>() as u32,
        memory_load: 0,
        total_phys: 0,
        avail_phys: 0,
        total_page_file: 0,
        avail_page_file: 0,
        total_virtual: 0,
        avail_virtual: 0,
        avail_extended_virtual: 0,
    };
    // SAFETY: `status` is a writable MEMORYSTATUSEX with its length set.
    if unsafe { GlobalMemoryStatusEx(&mut status) } == 0 {
        return Err(Failure::failed("cannot read host statistics"));
    }
    // SAFETY: a kernel32 call that takes no arguments.
    let ticks = unsafe { GetTickCount64() };
    let bytes = |n: u64| i64::try_from(n).unwrap_or(i64::MAX);
    let total = bytes(status.total_phys);
    let free = bytes(status.avail_phys).min(total);
    Ok(Metrics {
        total_memory: total,
        free_memory: free,
        available_memory: free,
        uptime_ns: bytes(ticks).saturating_mul(1_000_000),
        load: [0.0; 3],
        parallelism: crate::imp::cpu_count(),
    })
}

#[cfg(not(any(
    target_os = "linux",
    target_os = "android",
    target_os = "macos",
    windows
)))]
pub fn metrics() -> Result<Metrics, Failure> {
    Err(STATUS_UNSUPPORTED.into())
}
