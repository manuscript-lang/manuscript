//! Runtime fast paths as inlinable MIR: the string helpers of `rtstr`. Map and set lookups,
//! `String.view`, `String.slice`, `Bytes.view`, byte reads and searches are inlined by C passes over
//! the runtime call (`compiler/src/opt/opt_probe.c`, `opt_viewfast.c`, `opt_bytesfast.c`).

use crate::cx::HelperKey;
use crate::func::FnLower;
use ms_mir::builder::FuncBuilder;
use ms_mir::ir::{FuncId, Param, Value};
use ms_mir::types::Ty as MTy;

/// The one way a generated fast path is made: an internal function marked `inline(always)` that
/// does the common case itself and calls the runtime for the rest, built once per `HelperKey`.
/// Every inlinable runtime call (`inline_probe`, `inline_str`) goes through these three steps.
impl<'a> FnLower<'a> {
    pub(crate) fn fast_path_cached(&self, key: &HelperKey) -> Option<FuncId> {
        self.cx.helpers.get(key).copied()
    }

    pub(crate) fn fast_path_builder(
        &mut self,
        name: &str,
        params: Vec<Param>,
        ret: MTy,
    ) -> FuncBuilder<'_> {
        FuncBuilder::fast_path(self.b.m, name, params, ret)
    }

    pub(crate) fn fast_path_add(&mut self, key: HelperKey, func: ms_mir::ir::Func) -> FuncId {
        let fid = self.b.m.add_func(func);
        self.cx.helpers.insert(key, fid);
        fid
    }
}

impl FnLower<'_> {
    /// Calls the generated fast path for the runtime symbol `sym` when it has one: the string
    /// helpers of `rtstr`. The view, slice and byte fast paths are C passes over the runtime call.
    pub(crate) fn inline_probe(&mut self, sym: &str, args: &[Value], _ret: MTy) -> Option<Value> {
        if let Some(which) = self.str_fast(sym, args) {
            let f = self.str_fn(which);
            return Some(self.b.call(f, args));
        }
        // A literal needle of two or more bytes skips the dispatch on the needle's length.
        if sym == "msrt_string_contains"
            && let Some(id) = self.b.str_lit_of(args[1])
            && self.b.m.strings[id.0 as usize].len() >= 2
        {
            let ext = crate::text::runtime_fn(
                self.b.m,
                "msrt_string_contains_multi",
                &[MTy::STR, MTy::STR],
                MTy::BOOL,
            );
            return Some(self.b.call_rt(ext, args));
        }
        // Map and set lookups stay runtime calls: the `probe` pass inlines them.
        None
    }
}
