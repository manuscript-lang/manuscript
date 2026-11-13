//! The `declare` lines of the runtime functions the emitter calls by name. The module keeps the
//! first declaration of a symbol, so every area asks here and two areas cannot declare one
//! function differently.

use super::Cx;

/// The declaration of a heap function, which LLVM knows as an allocation family (`allockind`): a
/// block that is only stored to and freed is deleted, an allocation does not clobber the memory the
/// program can name (only the allocator's own state, `inaccessiblemem`), and the result neither
/// aliases nor needs a null check. Every spelling of these four goes through here, since the
/// module keeps the first declaration of a symbol.
pub(crate) fn heap_decl(name: &str) -> Option<&'static str> {
    Some(match name {
        "msrt_alloc" => {
            "declare noalias align 16 ptr @\"msrt_alloc\"(i64) nounwind \
             allockind(\"alloc,uninitialized,aligned\") allocsize(0) \"alloc-family\"=\"msrt\" \
             memory(inaccessiblemem: readwrite)"
        }
        "msrt_alloc_zeroed" => {
            "declare noalias align 16 ptr @\"msrt_alloc_zeroed\"(i64) nounwind \
             allockind(\"alloc,zeroed,aligned\") allocsize(0) \"alloc-family\"=\"msrt\" \
             memory(inaccessiblemem: readwrite)"
        }
        "msrt_realloc" => {
            "declare noalias align 16 ptr @\"msrt_realloc\"(ptr allocptr, i64) nounwind \
             allockind(\"realloc,aligned\") allocsize(1) \"alloc-family\"=\"msrt\" \
             memory(argmem: readwrite, inaccessiblemem: readwrite)"
        }
        "msrt_free" => {
            "declare void @\"msrt_free\"(ptr allocptr nocapture) nounwind \
             allockind(\"free\") \"alloc-family\"=\"msrt\" \
             memory(argmem: readwrite, inaccessiblemem: readwrite)"
        }
        _ => return None,
    })
}

/// The same four functions with no allocation semantics: ordinary calls that may touch any
/// memory, so LLVM keeps every allocation and free. A build that counts heap blocks (the
/// ownership-count gate) asks for these, since an elided block would not be counted.
pub(crate) fn plain_heap_decl(name: &str) -> Option<&'static str> {
    Some(match name {
        "msrt_alloc" => "declare noalias align 16 ptr @\"msrt_alloc\"(i64) nounwind",
        "msrt_alloc_zeroed" => "declare noalias align 16 ptr @\"msrt_alloc_zeroed\"(i64) nounwind",
        "msrt_realloc" => "declare noalias align 16 ptr @\"msrt_realloc\"(ptr, i64) nounwind",
        "msrt_free" => "declare void @\"msrt_free\"(ptr) nounwind",
        _ => return None,
    })
}

/// The declaration of a runtime function whose signature is fixed: every one takes and returns
/// `i64` words, except the allocator, which returns a fresh aligned block. None unwinds; the
/// faults never return.
fn text(name: &str) -> Option<&'static str> {
    Some(match name {
        "msrt_alloc" | "msrt_alloc_zeroed" | "msrt_realloc" | "msrt_free" => {
            return heap_decl(name);
        }
        "msrt_string_length" => "declare i64 @\"msrt_string_length\"(i64) nounwind",
        "msrt_task_grow" => "declare void @\"msrt_task_grow\"(i64, i64) nounwind",
        "msrt_cleanup_push" => "declare i64 @\"msrt_cleanup_push\"(i64, i64) nounwind",
        "msrt_obj_clone" => "declare i64 @\"msrt_obj_clone\"(i64) nounwind",
        "msrt_index_fault" => "declare void @\"msrt_index_fault\"(i64, i64) cold noreturn nounwind",
        _ => return None,
    })
}

/// Declares the fixed-signature runtime function `name`.
pub(super) fn declare(cx: &mut Cx, name: &str) {
    let decl = text(name).unwrap_or_else(|| panic!("`{name}` has no fixed declaration"));
    cx.decls.push((name.into(), decl.into()));
}

/// Declares a runtime function that never returns and takes `args` `i64` words.
pub(super) fn declare_fault(cx: &mut Cx, name: &str, args: usize) {
    let formals = vec!["i64"; args].join(", ");
    cx.decls.push((
        name.into(),
        format!("declare void @\"{name}\"({formals}) cold noreturn nounwind"),
    ));
}

#[cfg(test)]
mod tests {
    use super::{heap_decl, plain_heap_decl};

    /// The allocator is an `alloc-family`, and the plain spelling (heap facts off) is not.
    #[test]
    fn heap_functions_are_one_allocation_family() {
        for name in [
            "msrt_alloc",
            "msrt_alloc_zeroed",
            "msrt_realloc",
            "msrt_free",
        ] {
            let facts = heap_decl(name).expect("declared");
            assert!(facts.contains("\"alloc-family\"=\"msrt\"") && facts.contains("allockind"));
            let plain = plain_heap_decl(name).expect("declared");
            assert!(!plain.contains("allockind") && plain.contains(&format!("@\"{name}\"")));
        }
        assert!(heap_decl("msrt_free").unwrap().contains("(ptr allocptr"));
    }
}
