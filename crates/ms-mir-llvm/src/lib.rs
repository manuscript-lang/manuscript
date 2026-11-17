//! Standalone LLVM backend for MIR: emits LLVM IR text straight from MIR and depends on nothing
//! but the MIR crate. [`emit`] writes the functions, the glue they call and the data they address
//! (type descriptors, vtables, globals, shared enum blocks) into one or more LLVM modules; the
//! caller compiles them with LLVM and links the objects with the runtime.

mod abi_llvm;
mod glue_llvm;
mod llvm_build;
mod llvm_ir;
mod llvm_lifetimes;
mod mir_llvm;
mod program;
mod state;
mod tables;

pub use llvm_ir::{TEXT_ANCHOR, Void};
pub use program::emit;
pub use state::ENTRY_SYMBOL;
pub use tables::{TableFn, tables_unit};

pub use ms_mir::glue::{GLUE_PREFIX, Glue};

/// What [`emit`] needs to know about the build.
#[derive(Clone, Debug)]
pub struct Options {
    /// Emit overflow, division, bounds and unwrap checks.
    pub checks: bool,
    /// Declare the heap functions as an allocation family so LLVM can reason about them.
    pub heap_facts: bool,
    /// Fill each block-confined stack slot with a pattern where its lifetime ends.
    pub poison_slots: bool,
    /// How many modules to write; `None` picks one per core, by the size of the code.
    pub units: Option<usize>,
    /// The LLVM target triple.
    pub triple: String,
    /// The caller can address functions as offsets from [`TEXT_ANCHOR`], so they may be internal.
    pub anchor: bool,
}

/// A function the modules define, for the caller's fault and profile tables.
#[derive(Clone, Debug)]
pub struct FuncInfo {
    /// Linkage symbol.
    pub symbol: String,
    /// Display name (`glue` for generated glue).
    pub name: String,
    /// Index into the module's files, `u32::MAX` when unknown.
    pub file: u32,
    pub line: u32,
}

/// The LLVM modules of a program.
pub struct Program {
    pub units: Vec<Void>,
    /// Every function defined, source functions in order and then glue.
    pub funcs: Vec<FuncInfo>,
    /// The functions have no visible symbol: the single unit defines [`TEXT_ANCHOR`] and the
    /// caller addresses code as offsets from it.
    pub anchored: bool,
}

/// A failure to emit.
#[derive(Debug)]
pub struct Error(pub String);

impl std::fmt::Display for Error {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(&self.0)
    }
}

impl std::error::Error for Error {}

#[cfg(test)]
mod tests {
    /// The backend is standalone: it may depend on MIR and the runtime ABI only.
    #[test]
    fn depends_only_on_mir_and_the_runtime_abi() {
        let manifest =
            std::fs::read_to_string(concat!(env!("CARGO_MANIFEST_DIR"), "/Cargo.toml")).unwrap();
        let deps: Vec<&str> = manifest
            .lines()
            .skip_while(|l| l.trim() != "[dependencies]")
            .skip(1)
            .take_while(|l| !l.starts_with('['))
            .filter_map(|l| l.split('=').next().map(str::trim))
            .filter(|n| !n.is_empty())
            .collect();
        assert_eq!(deps, ["ms-mir", "ms-rt-abi"]);
    }
}
