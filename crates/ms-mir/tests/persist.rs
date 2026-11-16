use ms_mir::persist::OwnerSet;
use std::collections::BTreeSet;

/// A small deterministic generator, so a failure reproduces.
struct Rng(u64);

impl Rng {
    fn next(&mut self) -> u64 {
        self.0 = self
            .0
            .wrapping_mul(6364136223846793005)
            .wrapping_add(1442695040888963407);
        self.0 >> 33
    }
}

fn agree(set: &OwnerSet, model: &BTreeSet<u32>) {
    assert_eq!(set.to_vec(), model.iter().copied().collect::<Vec<_>>());
    assert_eq!(set.first(), model.iter().next().copied());
    assert_eq!(set.is_empty(), model.is_empty());
}

#[test]
fn follows_a_model_under_random_updates() {
    for (seed, range) in [(1, 40u64), (2, 700), (3, 20_000), (4, 3_000_000)] {
        let mut rng = Rng(seed);
        let (mut set, mut model) = (OwnerSet::new(), BTreeSet::new());
        for step in 0u32..4000 {
            let v = (rng.next() % range) as u32;
            if rng.next().is_multiple_of(3) {
                assert_eq!(set.remove(v), model.remove(&v), "remove {v}");
            } else {
                set.insert(v);
                model.insert(v);
            }
            assert_eq!(set.contains(v), model.contains(&v));
            if step.is_multiple_of(400) {
                agree(&set, &model);
            }
        }
        agree(&set, &model);
    }
}

#[test]
fn a_clone_is_unaffected_by_later_updates() {
    let mut a = OwnerSet::new();
    for v in [3, 70, 5000, 9_000_000] {
        a.insert(v);
    }
    let b = a.clone();
    a.remove(70);
    a.insert(8);
    assert_eq!(b.to_vec(), vec![3, 70, 5000, 9_000_000]);
    assert_eq!(a.to_vec(), vec![3, 8, 5000, 9_000_000]);
}

#[test]
fn equal_contents_are_equal_whatever_the_history() {
    let (mut a, mut b) = (OwnerSet::new(), OwnerSet::new());
    // `a` grew tall and shrank; `b` never left one leaf.
    a.insert(5_000_000);
    a.insert(1);
    a.remove(5_000_000);
    b.insert(1);
    assert_eq!(a, b);
    assert_eq!(b, a);
    b.insert(2);
    assert_ne!(a, b);
    a.insert(2);
    assert_eq!(a, b);
    assert_eq!(OwnerSet::new(), {
        let mut c = OwnerSet::new();
        c.insert(700);
        c.remove(700);
        c
    });
}

#[test]
fn reports_the_values_in_exactly_one_set() {
    let (mut a, mut b) = (OwnerSet::new(), OwnerSet::new());
    for v in [1, 2, 300] {
        a.insert(v);
    }
    for v in [2, 300, 4000] {
        b.insert(v);
    }
    assert_eq!(a.symmetric_difference(&b), vec![1, 4000]);
}

#[test]
fn removing_an_absent_value_changes_nothing() {
    let mut a = OwnerSet::new();
    assert!(!a.remove(9));
    a.insert(9);
    assert!(!a.remove(10));
    assert!(!a.remove(1_000_000));
    assert_eq!(a.to_vec(), vec![9]);
}

#[test]
fn a_position_map_follows_a_model() {
    use ms_mir::persist::PosMap;
    use std::collections::BTreeMap;
    for (seed, range) in [(5, 30u64), (6, 900), (7, 60_000)] {
        let mut rng = Rng(seed);
        let (mut map, mut model): (PosMap<u64>, BTreeMap<u32, u64>) =
            (PosMap::new(), BTreeMap::new());
        let keep = map.clone();
        for step in 0..3000u64 {
            let k = (rng.next() % range) as u32;
            if rng.next().is_multiple_of(3) {
                assert_eq!(map.remove(k), model.remove(&k).is_some(), "remove {k}");
            } else {
                map.insert(k, step);
                model.insert(k, step);
            }
            assert_eq!(map.get(k), model.get(&k));
            assert_eq!(map.len(), model.len());
        }
        assert_eq!(
            map.values().copied().collect::<Vec<_>>(),
            model.values().copied().collect::<Vec<_>>()
        );
        assert!(keep.is_empty(), "a clone is unaffected by later updates");
    }
}

#[test]
fn a_position_map_shares_what_it_does_not_change() {
    use ms_mir::persist::PosMap;
    let mut a: PosMap<u32> = PosMap::new();
    for k in 0..500 {
        a.insert(k, k);
    }
    let b = a.clone();
    assert!(a.same_tree(&b));
    a.insert(7, 70);
    assert!(!a.same_tree(&b));
    assert_eq!(b.get(7), Some(&7));
    assert_eq!(a.get(7), Some(&70));
}

#[test]
fn a_position_map_compares_entries_without_sharing() {
    use ms_mir::persist::PosMap;
    let (mut a, mut b): (PosMap<u32>, PosMap<u32>) = (PosMap::new(), PosMap::new());
    for k in 0..300 {
        a.insert(k, k * 2);
        b.insert(k, k * 2);
    }
    assert!(!a.same_tree(&b));
    assert!(a.same_entries(&b));
    b.insert(299, 1);
    assert!(!a.same_entries(&b));
    b.insert(299, 598);
    b.remove(0);
    assert!(!a.same_entries(&b));
}
