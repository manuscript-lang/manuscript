//! Cancel switches for `@std/concurrency/promise.ms`.
//!
//! A switch is one slot of a process-wide flat table, named by an id `(generation << 32) | (index + 1)`, so a
//! stale id never matches. It lists the promises made with its signal, from any thread. Firing it tells each
//! promise's own thread to stop it, the way a timeout does, so the work ends at its next wait.
use crate::promise;
use std::collections::BTreeSet;
use std::sync::Mutex;

struct Slot {
    generation: u32,
    live: bool,
    fired: bool,
    /// The promises registered with this switch.
    members: BTreeSet<i64>,
}

struct Table {
    slots: Vec<Slot>,
    free: Vec<usize>,
}

static TABLE: Mutex<Table> = Mutex::new(Table {
    slots: Vec::new(),
    free: Vec::new(),
});

fn table() -> std::sync::MutexGuard<'static, Table> {
    TABLE
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
}

fn slot(t: &mut Table, id: i64) -> Option<&mut Slot> {
    let i = usize::try_from((id & 0xffff_ffff) - 1).ok()?;
    let s = t.slots.get_mut(i)?;
    (s.live && s.generation == (id >> 32) as u32).then_some(s)
}

/// Makes a switch that has not fired.
#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_cancel_new() -> i64 {
    let mut t = table();
    let i = match t.free.pop() {
        Some(i) => i,
        None => {
            t.slots.push(Slot {
                generation: 0,
                live: false,
                fired: false,
                members: BTreeSet::new(),
            });
            t.slots.len() - 1
        }
    };
    let s = &mut t.slots[i];
    s.generation = s.generation.wrapping_add(1).max(1);
    s.live = true;
    s.fired = false;
    s.members.clear();
    (i64::from(s.generation) << 32) | (i as i64 + 1)
}

/// Fires the switch: every promise registered with it is stopped on its own thread. Firing twice, or a
/// switch that was freed, does nothing.
#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_cancel_fire(id: i64) {
    let members = {
        let mut t = table();
        let Some(s) = slot(&mut t, id) else { return };
        if s.fired {
            return;
        }
        s.fired = true;
        core::mem::take(&mut s.members)
    };
    for promise in members {
        promise::stop_on_owner(promise);
    }
}

/// Whether the switch has fired. A freed switch reads as not fired.
#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_cancel_fired(id: i64) -> u8 {
    u8::from(slot(&mut table(), id).is_some_and(|s| s.fired))
}

/// Frees the switch. Its promises stop listening and keep running; a signal left over reads as not fired.
#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_cancel_free(id: i64) {
    let mut t = table();
    let Some(s) = slot(&mut t, id) else { return };
    s.live = false;
    s.members.clear();
    let i = (id & 0xffff_ffff) as usize - 1;
    t.free.push(i);
}

/// Registers `promise` with the switch `id`. Answers true when the switch has already fired, so the
/// caller stops the promise itself.
pub(crate) fn register(id: i64, promise: i64) -> bool {
    let mut t = table();
    let Some(s) = slot(&mut t, id) else {
        return false;
    };
    if s.fired {
        return true;
    }
    s.members.insert(promise);
    false
}

/// Removes `promise` from the switch `id`, when it is dropped.
pub(crate) fn unregister(id: i64, promise: i64) {
    if let Some(s) = slot(&mut table(), id) {
        s.members.remove(&promise);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_switch_fires_once_and_a_freed_one_reads_as_not_fired() {
        let id = msrt_cancel_new();
        assert_eq!(msrt_cancel_fired(id), 0);
        assert!(!register(id, 7));
        msrt_cancel_fire(id);
        assert_eq!(msrt_cancel_fired(id), 1);
        assert!(register(id, 8));
        msrt_cancel_free(id);
        assert_eq!(msrt_cancel_fired(id), 0);
        let again = msrt_cancel_new();
        assert_ne!(again, id);
        assert_eq!(msrt_cancel_fired(id), 0);
        msrt_cancel_free(again);
    }
}
