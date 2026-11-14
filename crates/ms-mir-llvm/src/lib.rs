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

pub use llvm_ir::{TEXT_ANCHOR, Unit};
pub use program::emit;
pub use state::ENTRY_SYMBOL;
pub use tables::{TableFn, tables_unit};

/// The name prefix of generated glue functions, followed by a serial and the kind.
pub const GLUE_PREFIX: &str = "ms.glue.";

/// Offset of the first capture in a closure object.
pub(crate) const CLOSURE_CAPTURES: u32 = ms_rt_abi::CLOSURE_CAPTURES_OFFSET as u32;
/// Offset of `code` in a closure object.
pub(crate) const CLOSURE_CODE: i32 = ms_rt_abi::CLOSURE_CODE_OFFSET as i32;

/// Kinds of generated helper functions.
#[derive(Clone, Copy, PartialEq, Eq, Hash, Debug)]
pub enum Glue {
    /// Drops a value (takes the value's leaves).
    Drop,
    /// Clones a value (takes and returns the value's leaves).
    Clone,
    /// Closure object destructor `fn(obj)`; the `Ty` is unused (`Ty::UNIT`) and the key carries the function id.
    ClosureDrop(u32),
    /// Like `ClosureDrop` for an object in a stack frame: drops the captures, frees nothing.
    ClosureDropFramed(u32),
    /// `fn(obj)` that releases a closure object after capture `k` while a fault unwinds out of the
    /// close of that capture (whose value that close owns): it drops the later captures without
    /// closing them and frees the object.
    ClosureDropFrom(u32, u32),
    /// Closure object clone entry `fn(obj) -> obj`, cloning the captures; keyed like `ClosureDrop`.
    ClosureClone(u32),
    /// Heap block destructor of an interface payload `fn(block)`.
    BlockDrop,
    /// Clone of an interface payload block `fn(block) -> block`.
    BlockClone,
    /// `fn(arg: *mut u8)` thunk used by cleanup.push; key carries the closer function.
    CleanupThunk(u32),
    /// `fn(block)` that calls the function in the key with the parameters stored at `block` and
    /// stores its results after them: the body `msrt_task_grow` runs on a new stack segment.
    GrowShim(u32),
    /// `fn(slot)` that drops the value stored in memory at `slot` (descriptor `drop`).
    SlotDrop,
    /// `fn(src, dst)` that copies the value at `src` into uninitialised `dst` (descriptor `copy`).
    SlotCopy,
}

impl Glue {
    /// The kind's part of a glue symbol.
    pub(crate) fn suffix(self) -> &'static str {
        match self {
            Glue::Drop => "drop",
            Glue::Clone => "clone",
            Glue::ClosureDrop(_) => "closure_drop",
            Glue::ClosureDropFramed(_) => "closure_drop_framed",
            Glue::ClosureDropFrom(..) => "closure_drop_from",
            Glue::ClosureClone(_) => "closure_clone",
            Glue::BlockDrop => "block_drop",
            Glue::BlockClone => "block_clone",
            Glue::CleanupThunk(_) => "cleanup_thunk",
            Glue::GrowShim(_) => "grow_shim",
            Glue::SlotDrop => "slot_drop",
            Glue::SlotCopy => "slot_copy",
        }
    }
}

/// What [`emit`] needs to know about the build.
#[derive(Clone, Debug)]
pub struct Options {
    /// Emit overflow, division, bounds and unwrap checks.
    pub checks: bool,
    /// Declare the heap functions as an allocation family so LLVM can reason about them.
    pub heap_facts: bool,
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
    pub units: Vec<Unit>,
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
