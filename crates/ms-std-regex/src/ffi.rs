//! C ABI shims for `@std/regex.ms`. Symbols are `msrt_regex_<function>`; a compiled `Regex` is a
//! runtime handle object (`Obj` header + boxed state).
#![allow(unsafe_code, clippy::missing_safety_doc)]

use crate::Regex;
use alloc::boxed::Box;
use ms_rt_abi::Obj;
use ms_std_core::{StrObj, VecVal, new_string, opt, status_of, str_ref, write_string_list};

unsafe extern "C" {
    fn msrt_alloc(size: usize) -> *mut u8;
    fn msrt_free(p: *mut u8);
}

#[repr(C)]
pub struct RegexObj {
    header: Obj,
    state: *mut Regex,
}

unsafe extern "C" fn regex_drop(o: *mut Obj) {
    let r = o.cast::<RegexObj>();
    // SAFETY: `o` was built by `msrt_regex_compile`; `state` came from `Box::into_raw`.
    unsafe {
        drop(Box::from_raw((*r).state));
        msrt_free(o.cast());
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_regex_compile(pattern: *const StrObj, out: *mut *mut RegexObj) -> u8 {
    // SAFETY: `pattern` is a live string.
    let r = crate::compile(unsafe { str_ref(pattern) });
    match r {
        Ok(re) => {
            // SAFETY: allocation sized for `RegexObj`, initialised before publication; `out` writable.
            unsafe {
                let p = msrt_alloc(core::mem::size_of::<RegexObj>()).cast::<RegexObj>();
                p.write(RegexObj {
                    header: Obj {
                        rc: 1,
                        drop: Some(regex_drop),
                    },
                    state: Box::into_raw(Box::new(re)),
                });
                out.write(p);
            }
            0
        }
        Err(e) => e.status(),
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_regex_matches(re: *const RegexObj, text: *const StrObj) -> u8 {
    // SAFETY: `re` is a live handle and `text` a live string.
    u8::from(unsafe { (*(*re).state).is_match(str_ref(text)) })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_regex_find_all(
    re: *const RegexObj,
    text: *const StrObj,
    has_max: u8,
    max: i64,
    out: *mut VecVal,
) -> u8 {
    // SAFETY: `re`/`text` are live; `out` is writable.
    let r = unsafe { (*(*re).state).find_all(str_ref(text), opt(has_max, max)) };
    if let Ok(list) = &r {
        // SAFETY: `out` is writable by the caller contract.
        unsafe { write_string_list(out, list) };
    }
    status_of(&r)
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_regex_replace_all(
    re: *const RegexObj,
    text: *const StrObj,
    replacement: *const StrObj,
    has_max: u8,
    max: i64,
    out: *mut *mut StrObj,
) -> u8 {
    // SAFETY: arguments are live; `out` is writable.
    let r = unsafe {
        (*(*re).state).replace_all(str_ref(text), str_ref(replacement), opt(has_max, max))
    };
    if let Ok(s) = &r {
        // SAFETY: `out` is writable by the caller contract.
        unsafe { out.write(new_string(s)) };
    }
    status_of::<alloc::string::String>(&r)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn compile_match_release() {
        let pat = new_string("a+");
        let hay = new_string("baab");
        let mut re = core::ptr::null_mut();
        // SAFETY: strings and handle are live for each call; released through the runtime.
        unsafe {
            assert_eq!(msrt_regex_compile(pat, &mut re), 0);
            assert_eq!(msrt_regex_matches(re, hay), 1);
            let mut out = core::mem::MaybeUninit::<VecVal>::uninit();
            assert_eq!(msrt_regex_find_all(re, hay, 0, 0, out.as_mut_ptr()), 0);
            assert_eq!(out.assume_init().len, 1);
            let bad = new_string("(");
            let mut none = core::ptr::null_mut();
            assert_eq!(
                msrt_regex_compile(bad, &mut none),
                ms_std_core::STATUS_INVALID_DATA
            );
            ms_rt::obj::msrt_release(re.cast());
            ms_rt::obj::msrt_release(pat.cast());
            ms_rt::obj::msrt_release(hay.cast());
            ms_rt::obj::msrt_release(bad.cast());
        }
    }
}
