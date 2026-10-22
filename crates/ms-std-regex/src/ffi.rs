//! C ABI shims for `@std/string.ms`. Symbols are `msrt_regex_<function>`; a compiled `Regex` is a
//! runtime handle object (`Obj` header + boxed state).

use crate::Regex;
use alloc::string::String;
use alloc::vec::Vec;
use ms_std_core::{Fail, IntList, ObjRef, Object, StrMap, abi_handle, native};

abi_handle!(Regex);

native! {
    fn msrt_regex_compile(pattern: &str) -> Result<Object<Regex>, Fail> {
        crate::compile(pattern).map(Object)
    }

    fn msrt_regex_matches(re: ObjRef<Regex>, text: &str) -> bool {
        re.is_match(text)
    }

    fn msrt_regex_find_all(
        re: ObjRef<Regex>,
        text: &str,
        has_max: bool,
        max: i64,
    ) -> Result<Vec<String>, Fail> {
        re.find_all(text, has_max.then_some(max))
    }

    fn msrt_regex_captures(re: ObjRef<Regex>, text: &str) -> Result<Vec<String>, Fail> {
        Ok(re.captures(text))
    }

    fn msrt_regex_captures_all(
        re: ObjRef<Regex>,
        text: &str,
        has_max: bool,
        max: i64,
    ) -> Result<Vec<Vec<String>>, Fail> {
        re.captures_all(text, has_max.then_some(max))
    }

    fn msrt_regex_named_captures(re: ObjRef<Regex>, text: &str) -> Result<StrMap, Fail> {
        Ok(StrMap(re.named_captures(text)))
    }

    fn msrt_regex_find_span(re: ObjRef<Regex>, text: &str) -> Result<IntList, Fail> {
        Ok(IntList(re.find_span(text)))
    }

    fn msrt_regex_split(
        re: ObjRef<Regex>,
        text: &str,
        has_max: bool,
        max: i64,
    ) -> Result<Vec<String>, Fail> {
        re.split(text, has_max.then_some(max))
    }

    fn msrt_regex_replace_template(
        re: ObjRef<Regex>,
        text: &str,
        template: &str,
        has_max: bool,
        max: i64,
    ) -> Result<String, Fail> {
        re.replace_template(text, template, has_max.then_some(max))
    }

    fn msrt_regex_replace_all(
        re: ObjRef<Regex>,
        text: &str,
        replacement: &str,
        has_max: bool,
        max: i64,
    ) -> Result<String, Fail> {
        re.replace_all(text, replacement, has_max.then_some(max))
    }
}

#[cfg(test)]
#[allow(unsafe_code)]
mod tests {
    use super::*;
    use ms_std_core::{VecVal, new_string};

    #[test]
    fn compile_match_release() {
        let pat = new_string("a+");
        let hay = new_string("baab");
        let mut re = core::ptr::null_mut();
        // SAFETY: strings and handle are live for each call; released through the runtime.
        unsafe {
            assert_eq!(msrt_regex_compile(&pat, &mut re), 0);
            assert_eq!(msrt_regex_matches(re, &hay), 1);
            let mut out = core::mem::MaybeUninit::<VecVal>::uninit();
            assert_eq!(msrt_regex_find_all(re, &hay, 0, 0, out.as_mut_ptr()), 0);
            assert_eq!(out.assume_init().len, 1);
            let bad = new_string("(");
            let mut none = core::ptr::null_mut();
            assert_eq!(
                msrt_regex_compile(&bad, &mut none),
                ms_std_core::STATUS_INVALID_DATA
            );
            ms_rt::obj::msrt_release(re.cast());
            ms_std_core::str_release(pat);
            ms_std_core::str_release(hay);
            ms_std_core::str_release(bad);
        }
    }
}
