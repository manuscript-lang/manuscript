//! Build settings read from the environment, once, when the engine is created. Everything below
//! the command line receives them as a [`BuildOptions`] value.

use ms_build::{BuildOptions, CopyProbe, RtHot};
use std::path::PathBuf;

/// The settings the `MS_*` build variables select; unset variables keep the defaults.
pub fn from_env() -> BuildOptions {
    let var = |name: &str| std::env::var_os(name);
    let path = |name: &str| var(name).filter(|v| !v.is_empty()).map(PathBuf::from);
    let text = |name: &str| var(name).and_then(|v| v.into_string().ok());
    BuildOptions {
        cranelift_only: text("MS_BACKEND").is_some_and(|b| b == "cranelift"),
        llvm_units: text("MS_LLVM_UNITS").and_then(|v| v.parse().ok()),
        vectorize: !text("MS_VECTORIZE").is_some_and(|v| v == "off" || v == "0"),
        heap_facts: !text("MS_HEAP_FACTS").is_some_and(|v| v == "off" || v == "0"),
        llvm_verify: var("MS_LLVM_VERIFY").is_some_and(|v| v != "0"),
        keep_ll: var("MS_KEEP_LL").is_some(),
        rt_hot: match var("MS_RT_HOT") {
            None => RtHot::Embedded,
            Some(v) if v == "1" => RtHot::Embedded,
            Some(v) if v == "0" => RtHot::Off,
            Some(v) => RtHot::File(PathBuf::from(v)),
        },
        llvm_tools: path("MS_LLVM_TOOLS"),
        lld: path("MS_LLD"),
        runtime: var("MS_RT_LIB").map(PathBuf::from),
        static_musl: false,
        timings: var("MS_TIMINGS").is_some_and(|v| v != "0"),
        dump_clif: var("MS_DUMP_CLIF").is_some_and(|v| v != "0"),
        copy_probe: match var("MS_COPY_PROBE") {
            Some(v) if v == "strict" => CopyProbe::Strict,
            Some(v) if v != "0" => CopyProbe::Report,
            _ => CopyProbe::Off,
        },
    }
}
