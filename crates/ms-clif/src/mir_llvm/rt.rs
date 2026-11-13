//! The `declare` lines of the runtime functions the emitter calls by name. The module keeps the
//! first declaration of a symbol, so every area asks here and two areas cannot declare one
//! function differently.

use super::Cx;

/// The declaration of a runtime function whose signature is fixed: every one takes and returns
/// `i64` words, except the allocator, which returns a fresh aligned block. None unwinds; the
/// faults never return.
fn text(name: &str) -> Option<&'static str> {
    Some(match name {
        "msrt_alloc" => "declare noalias align 16 ptr @\"msrt_alloc\"(i64) nounwind",
        "msrt_realloc" => "declare noalias align 16 ptr @\"msrt_realloc\"(i64, i64) nounwind",
        "msrt_string_length" => "declare i64 @\"msrt_string_length\"(i64) nounwind",
        "msrt_free" => "declare void @\"msrt_free\"(i64) nounwind",
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
