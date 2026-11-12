//! One integration-test binary for the crate: each file below is a module of it, so the
//! crate links once instead of once per file.

mod copies;
mod elaborate;
mod intern;
mod interp;
mod opt_bytetake;
mod opt_copyelim;
mod opt_ifconv;
mod opt_inline;
mod opt_lastuse;
mod opt_loopslot;
mod opt_overflow;
mod opt_range;
mod opt_reserve;
mod opt_simplify;
mod opt_strfuse;
mod outline;
mod text;
mod unwind;
