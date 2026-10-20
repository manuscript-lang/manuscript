//! Hosts without termios have no raw terminal; every operation answers `Unsupported`.

use crate::decoder::Event;
use ms_rt_abi::STATUS_UNSUPPORTED;

pub struct Raw;

impl Raw {
    pub fn open(_: i32, _: i32, _: bool) -> Result<Raw, u8> {
        Err(STATUS_UNSUPPORTED)
    }

    pub fn close(&self) {}

    pub fn size(&self) -> Result<(i64, i64), u8> {
        Err(STATUS_UNSUPPORTED)
    }

    pub fn move_cursor(&self, _: i64, _: i64) -> u8 {
        STATUS_UNSUPPORTED
    }

    pub fn show_cursor(&self, _: bool) -> u8 {
        STATUS_UNSUPPORTED
    }

    pub fn erase(&self, _: i64) -> u8 {
        STATUS_UNSUPPORTED
    }

    pub fn next_event(&self, _: Option<i64>, _: &mut Option<Event>) -> u8 {
        STATUS_UNSUPPORTED
    }
}
