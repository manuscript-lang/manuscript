//! Go's unstable `sort.Slice` (pattern-defeating quicksort), reproduced step
//! for step so that elements that compare equal land in the same order Go puts
//! them. Source tools sort with it wherever Go does, because the order of ties
//! is observable in their output.

#[derive(PartialEq, Clone, Copy)]
enum Hint {
    Unknown,
    Increasing,
    Decreasing,
}

/// Sorts `data` like Go's `sort.Slice(data, func(i, j) bool { less(&data[i], &data[j]) })`.
pub fn slice<T>(data: &mut [T], less: impl Fn(&T, &T) -> bool) {
    let length = data.len();
    let limit = (usize::BITS - length.leading_zeros()) as usize;
    let mut s = Sorter { data, less };
    s.pdqsort(0, length, limit);
}

struct Sorter<'a, T, F> {
    data: &'a mut [T],
    less: F,
}

impl<T, F: Fn(&T, &T) -> bool> Sorter<'_, T, F> {
    fn less(&self, i: usize, j: usize) -> bool {
        (self.less)(&self.data[i], &self.data[j])
    }

    fn swap(&mut self, i: usize, j: usize) {
        self.data.swap(i, j);
    }

    fn insertion_sort(&mut self, a: usize, b: usize) {
        for i in a + 1..b {
            let mut j = i;
            while j > a && self.less(j, j - 1) {
                self.swap(j, j - 1);
                j -= 1;
            }
        }
    }

    fn sift_down(&mut self, lo: usize, hi: usize, first: usize) {
        let mut root = lo;
        loop {
            let mut child = 2 * root + 1;
            if child >= hi {
                break;
            }
            if child + 1 < hi && self.less(first + child, first + child + 1) {
                child += 1;
            }
            if !self.less(first + root, first + child) {
                return;
            }
            self.swap(first + root, first + child);
            root = child;
        }
    }

    fn heap_sort(&mut self, a: usize, b: usize) {
        let first = a;
        let lo = 0;
        let hi = b - a;
        let mut i = (hi as isize - 1) / 2;
        while i >= 0 {
            self.sift_down(i as usize, hi, first);
            i -= 1;
        }
        let mut i = hi as isize - 1;
        while i >= 0 {
            self.swap(first, first + i as usize);
            self.sift_down(lo, i as usize, first);
            i -= 1;
        }
    }

    fn pdqsort(&mut self, mut a: usize, mut b: usize, mut limit: usize) {
        const MAX_INSERTION: usize = 12;
        let mut was_balanced = true;
        let mut was_partitioned = true;
        loop {
            let length = b - a;
            if length <= MAX_INSERTION {
                self.insertion_sort(a, b);
                return;
            }
            if limit == 0 {
                self.heap_sort(a, b);
                return;
            }
            if !was_balanced {
                self.break_patterns(a, b);
                limit -= 1;
            }
            let (mut pivot, mut hint) = self.choose_pivot(a, b);
            if hint == Hint::Decreasing {
                self.reverse_range(a, b);
                pivot = (b - 1) - (pivot - a);
                hint = Hint::Increasing;
            }
            if was_balanced
                && was_partitioned
                && hint == Hint::Increasing
                && self.partial_insertion_sort(a, b)
            {
                return;
            }
            if a > 0 && !self.less(a - 1, pivot) {
                a = self.partition_equal(a, b, pivot);
                continue;
            }
            let (mid, already) = self.partition(a, b, pivot);
            was_partitioned = already;
            let (left_len, right_len) = (mid - a, b - mid);
            let balance_threshold = length / 8;
            if left_len < right_len {
                was_balanced = left_len >= balance_threshold;
                self.pdqsort(a, mid, limit);
                a = mid + 1;
            } else {
                was_balanced = right_len >= balance_threshold;
                self.pdqsort(mid + 1, b, limit);
                b = mid;
            }
        }
    }

    fn partition(&mut self, a: usize, b: usize, pivot: usize) -> (usize, bool) {
        self.swap(a, pivot);
        let (mut i, mut j) = (a as isize + 1, b as isize - 1);
        while i <= j && self.less(i as usize, a) {
            i += 1;
        }
        while i <= j && !self.less(j as usize, a) {
            j -= 1;
        }
        if i > j {
            self.swap(j as usize, a);
            return (j as usize, true);
        }
        self.swap(i as usize, j as usize);
        i += 1;
        j -= 1;
        loop {
            while i <= j && self.less(i as usize, a) {
                i += 1;
            }
            while i <= j && !self.less(j as usize, a) {
                j -= 1;
            }
            if i > j {
                break;
            }
            self.swap(i as usize, j as usize);
            i += 1;
            j -= 1;
        }
        self.swap(j as usize, a);
        (j as usize, false)
    }

    fn partition_equal(&mut self, a: usize, b: usize, pivot: usize) -> usize {
        self.swap(a, pivot);
        let (mut i, mut j) = (a as isize + 1, b as isize - 1);
        loop {
            while i <= j && !self.less(a, i as usize) {
                i += 1;
            }
            while i <= j && self.less(a, j as usize) {
                j -= 1;
            }
            if i > j {
                break;
            }
            self.swap(i as usize, j as usize);
            i += 1;
            j -= 1;
        }
        i as usize
    }

    fn partial_insertion_sort(&mut self, a: usize, b: usize) -> bool {
        const MAX_STEPS: usize = 5;
        const SHORTEST_SHIFTING: usize = 50;
        let mut i = a + 1;
        for _ in 0..MAX_STEPS {
            while i < b && !self.less(i, i - 1) {
                i += 1;
            }
            if i == b {
                return true;
            }
            if b - a < SHORTEST_SHIFTING {
                return false;
            }
            self.swap(i, i - 1);
            if i - a >= 2 {
                let mut j = i - 1;
                while j >= 1 {
                    if !self.less(j, j - 1) {
                        break;
                    }
                    self.swap(j, j - 1);
                    j -= 1;
                }
            }
            if b - i >= 2 {
                for j in i + 1..b {
                    if !self.less(j, j - 1) {
                        break;
                    }
                    self.swap(j, j - 1);
                }
            }
        }
        false
    }

    fn break_patterns(&mut self, a: usize, b: usize) {
        let length = b - a;
        if length >= 8 {
            let mut random = length as u64;
            let modulus = 1usize << (usize::BITS - length.leading_zeros());
            let mut idx = a + (length / 4) * 2 - 1;
            while idx <= a + (length / 4) * 2 + 1 {
                random ^= random << 13;
                random ^= random >> 7;
                random ^= random << 17;
                let mut other = (random as usize) & (modulus - 1);
                if other >= length {
                    other -= length;
                }
                self.swap(idx, a + other);
                idx += 1;
            }
        }
    }

    fn choose_pivot(&mut self, a: usize, b: usize) -> (usize, Hint) {
        const SHORTEST_NINTHER: usize = 50;
        const MAX_SWAPS: usize = 4 * 3;
        let l = b - a;
        let mut swaps = 0usize;
        let mut i = a + l / 4;
        let mut j = a + l / 4 * 2;
        let mut k = a + l / 4 * 3;
        if l >= 8 {
            if l >= SHORTEST_NINTHER {
                i = self.median(i - 1, i, i + 1, &mut swaps);
                j = self.median(j - 1, j, j + 1, &mut swaps);
                k = self.median(k - 1, k, k + 1, &mut swaps);
            }
            j = self.median(i, j, k, &mut swaps);
        }
        match swaps {
            0 => (j, Hint::Increasing),
            MAX_SWAPS => (j, Hint::Decreasing),
            _ => (j, Hint::Unknown),
        }
    }

    fn order2(&self, a: usize, b: usize, swaps: &mut usize) -> (usize, usize) {
        if self.less(b, a) {
            *swaps += 1;
            return (b, a);
        }
        (a, b)
    }

    fn median(&self, a: usize, b: usize, c: usize, swaps: &mut usize) -> usize {
        let (a, b) = self.order2(a, b, swaps);
        let (b, c) = self.order2(b, c, swaps);
        let _ = c;
        let (_a, b) = self.order2(a, b, swaps);
        b
    }

    fn reverse_range(&mut self, a: usize, b: usize) {
        let (mut i, mut j) = (a, b - 1);
        while i < j {
            self.swap(i, j);
            i += 1;
            j -= 1;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::slice;

    /// Go: sort.Slice over 40 (key, index) pairs with ten distinct keys.
    #[test]
    fn sorts_by_key() {
        let mut v: Vec<(u32, u32)> = (0..200).map(|i| ((i * 7919) % 10, i)).collect();
        slice(&mut v, |a, b| a.0 < b.0);
        assert!(v.windows(2).all(|w| w[0].0 <= w[1].0));
    }
}

#[cfg(test)]
mod parity {
    use super::slice;

    /// Checksums produced by Go's `sort.Slice` over the same inputs.
    #[test]
    fn ties_land_where_go_puts_them() {
        let expected: &[(usize, usize, u64)] = &[
            (5, 2, 127957),
            (5, 5, 244471),
            (5, 17, 247230),
            (13, 2, 631994420),
            (13, 5, 985847504),
            (13, 17, 384128152),
            (30, 2, 489415055),
            (30, 5, 400762009),
            (30, 17, 966509006),
            (51, 2, 529090407),
            (51, 5, 498872111),
            (51, 17, 85479159),
            (100, 2, 928293760),
            (100, 5, 692915707),
            (100, 17, 556134195),
            (300, 2, 32001868),
            (300, 5, 409605787),
            (300, 17, 272727649),
            (1000, 2, 772196725),
            (1000, 5, 763860968),
            (1000, 17, 933836881),
        ];
        for &(n, m, want) in expected {
            let mut v: Vec<(usize, usize)> = (0..n).map(|i| ((i * 7919 + i / 3) % m, i)).collect();
            slice(&mut v, |a, b| a.0 < b.0);
            let mut s = 0u64;
            for (j, p) in v.iter().enumerate() {
                s = (s * 31 + (p.1 * (j + 1)) as u64) % 1_000_000_007;
            }
            assert_eq!(s, want, "n={n} m={m}");
        }
    }
}
