//! Proofs over the analysis results: relation queries, goal proving and the edits they justify.

use super::*;

impl Fa<'_> {
    /// `(a < b, a <= b)` as far as recorded relations and identity prove.
    pub(super) fn rel_known(&self, a: Value, b: Value, env: &Env) -> (bool, bool) {
        let mut lt = false;
        let mut le = self.same_value(a, b);
        for &(x, y, strict) in &env.rels {
            if self.same_value(x, a) && self.same_value(y, b) {
                lt |= strict;
                le = true;
            }
        }
        (lt, le)
    }

    pub(super) fn same_value(&self, a: Value, b: Value) -> bool {
        a == b
            || self
                .lenof
                .get(&a)
                .is_some_and(|l| self.lenof.get(&b) == Some(l))
    }

    pub(super) fn decide(
        &self,
        cc: Cc,
        a: Value,
        b: Value,
        x: Itv,
        y: Itv,
        env: &Env,
    ) -> Option<bool> {
        let (lt, le) = self.rel_known(a, b, env);
        let (gt, ge) = self.rel_known(b, a, env);
        let (ilt, ile) = (x.hi < y.lo, x.hi <= y.lo);
        let (igt, ige) = (x.lo > y.hi, x.lo >= y.hi);
        let eq_true = (x.is_point() && y.is_point() && x.lo == y.lo) || self.same_value(a, b);
        let ne_true = ilt || igt || lt || gt;
        match cc {
            Cc::Lt if ilt || lt => Some(true),
            Cc::Lt if ige || ge => Some(false),
            Cc::Le if ile || le => Some(true),
            Cc::Le if igt || gt => Some(false),
            Cc::Gt if igt || gt => Some(true),
            Cc::Gt if ile || le => Some(false),
            Cc::Ge if ige || ge => Some(true),
            Cc::Ge if ilt || lt => Some(false),
            Cc::Eq if eq_true => Some(true),
            Cc::Eq if ne_true => Some(false),
            Cc::Ne if ne_true => Some(true),
            Cc::Ne if eq_true => Some(false),
            _ => None,
        }
    }

    /// Proves `idx < list.len l` from recorded relations.
    pub(super) fn below_len(&self, idx: Value, l: Value, env: &Env) -> bool {
        if let (Some(i), Some(n)) = (self.get(idx, env), self.list_length(l))
            && i.hi < n
        {
            return true;
        }
        let goal = Goal::Len(self.lengths[l.index()]);
        self.prove_le(idx, goal, -1, env, &mut Vec::new(), &mut { PROOF_FUEL })
    }

    /// Proves `idx >= 0` where the interval alone cannot, for `idx = x - y` with `y <= x`.
    pub(super) fn nonneg(&self, idx: Value, env: &Env) -> bool {
        if self.get(idx, env).is_some_and(|i| i.lo >= 0) {
            return true;
        }
        let Some(d) = self.def_inst(idx) else {
            return false;
        };
        match d.op {
            Op::ISub | Op::ISubChk if self.no_wrap(d, env) => self.prove_le(
                d.args[1],
                Goal::Val(d.args[0]),
                0,
                env,
                &mut Vec::new(),
                &mut { PROOF_FUEL },
            ),
            _ => false,
        }
    }

    /// Whether the add, subtract or multiply `d` computes the exact integer result.
    pub(super) fn no_wrap(&self, d: &Inst, env: &Env) -> bool {
        if matches!(d.op, Op::IAddChk | Op::ISubChk | Op::IMulChk) {
            return true;
        }
        let (Some(x), Some(y)) = (self.get(d.args[0], env), self.get(d.args[1], env)) else {
            return false;
        };
        let (lo, hi) = match d.op {
            Op::IAdd => (x.lo as i128 + y.lo as i128, x.hi as i128 + y.hi as i128),
            Op::ISub => (x.lo as i128 - y.hi as i128, x.hi as i128 - y.lo as i128),
            Op::IMul => corners(|a, b| a * b, x, y),
            _ => return false,
        };
        fits(lo, hi)
    }

    pub(super) fn goal_matches(&self, v: Value, goal: Goal) -> bool {
        match goal {
            Goal::Val(t) => v == t || self.same_value(v, t),
            Goal::Len(o) => self.lenof.get(&v) == Some(&o),
        }
    }

    /// Folds a constant offset in the goal value into `d`: `v <= (x + c) + d` is `v <= x + (c + d)`.
    pub(super) fn normalize_goal(&self, goal: Goal, d: i128, env: &Env) -> (Goal, i128) {
        let (mut goal, mut d) = (goal, d);
        for _ in 0..4 {
            let Goal::Val(t) = goal else { break };
            let Some(def) = self.def_inst(t) else { break };
            let step = match def.op {
                Op::IAdd | Op::IAddChk | Op::ISub | Op::ISubChk if self.no_wrap(def, env) => {
                    let sub = matches!(def.op, Op::ISub | Op::ISubChk);
                    match (self.constant(def.args[1]), self.constant(def.args[0])) {
                        (Some(c), _) => {
                            Some((def.args[0], if sub { -(c as i128) } else { c as i128 }))
                        }
                        (None, Some(c)) if !sub => Some((def.args[1], c as i128)),
                        _ => None,
                    }
                }
                _ => None,
            };
            let Some((x, c)) = step else { break };
            goal = Goal::Val(x);
            d += c;
        }
        (goal, d)
    }

    /// Proves `v <= goal + d` from intervals, recorded relations and the definitions of
    /// the values involved. A loop parameter is proved by induction: assuming the bound,
    /// every incoming argument must meet it too.
    pub(super) fn prove_le(
        &self,
        v: Value,
        goal: Goal,
        d: i128,
        env: &Env,
        assumed: &mut Vec<(Value, Goal, i128)>,
        fuel: &mut u32,
    ) -> bool {
        if *fuel == 0 {
            return false;
        }
        *fuel -= 1;
        let (goal, d) = self.normalize_goal(goal, d, env);
        if self.goal_matches(v, goal) && d >= 0 {
            return true;
        }
        if let Some(i) = self.get(v, env) {
            let floor = match goal {
                Goal::Val(t) => self.get(t, env).map(|g| g.lo as i128),
                Goal::Len(_) => Some(
                    env.itv
                        .iter()
                        .filter(|(l, _)| self.goal_matches(**l, goal))
                        .map(|(_, g)| g.lo.max(0) as i128)
                        .max()
                        .unwrap_or(0),
                ),
            };
            if floor.is_some_and(|f| i.hi as i128 <= f + d) {
                return true;
            }
        }
        if assumed
            .iter()
            .any(|&(av, ag, ad)| av == v && ag == goal && ad <= d)
        {
            return true;
        }
        for &(a, b, strict) in &env.rels {
            if self.same_value(a, v)
                && self.prove_le(b, goal, d + strict as i128, env, assumed, fuel)
            {
                return true;
            }
        }
        if let Some((bi, pi)) = self.param_of[v.index()]
            && !self.incoming[bi].is_empty()
        {
            assumed.push((v, goal, d));
            let all = self.incoming[bi].iter().all(|(pred, kind, args)| {
                let mut edge = self.edge_env(*pred, *kind);
                self.carry_goal_facts(goal, bi, env, &mut edge);
                self.prove_le(args[pi], goal, d, &edge, assumed, fuel)
            });
            assumed.pop();
            if all {
                return true;
            }
        }
        let Some(def) = self.def_inst(v) else {
            return false;
        };
        let hi_of = |x: Value| self.get(x, env).map(|i| i.hi as i128);
        let lo_of = |x: Value| self.get(x, env).map(|i| i.lo as i128);
        match def.op {
            Op::IAdd | Op::IAddChk if self.no_wrap(def, env) => {
                let (x, y) = (def.args[0], def.args[1]);
                hi_of(y).is_some_and(|h| self.prove_le(x, goal, d - h, env, assumed, fuel))
                    || hi_of(x).is_some_and(|h| self.prove_le(y, goal, d - h, env, assumed, fuel))
            }
            Op::ISub | Op::ISubChk if self.no_wrap(def, env) => {
                let (x, y) = (def.args[0], def.args[1]);
                lo_of(y).is_some_and(|l| self.prove_le(x, goal, d + l, env, assumed, fuel))
            }
            Op::SDiv | Op::SDivChk => {
                let (x, c) = (def.args[0], self.constant(def.args[1]));
                c.is_some_and(|c| c >= 1)
                    && lo_of(x).is_some_and(|l| l >= 0)
                    && self.prove_le(x, goal, d, env, assumed, fuel)
            }
            Op::SRem | Op::SRemChk => {
                let (x, y) = (def.args[0], def.args[1]);
                lo_of(x).is_some_and(|l| l >= 0)
                    && lo_of(y).is_some_and(|l| l >= 1)
                    && (self.prove_le(x, goal, d, env, assumed, fuel)
                        || self.prove_le(y, goal, d + 1, env, assumed, fuel))
            }
            Op::And => {
                let (x, y) = (def.args[0], def.args[1]);
                (lo_of(x).is_some_and(|l| l >= 0) && self.prove_le(x, goal, d, env, assumed, fuel))
                    || (lo_of(y).is_some_and(|l| l >= 0)
                        && self.prove_le(y, goal, d, env, assumed, fuel))
            }
            Op::Select => {
                self.prove_le(def.args[1], goal, d, env, assumed, fuel)
                    && self.prove_le(def.args[2], goal, d, env, assumed, fuel)
            }
            Op::IMul | Op::IMulChk if self.no_wrap(def, env) => {
                self.prove_scaled(def, goal, d, env)
            }
            _ => false,
        }
    }

    /// Copies what `env` knows about the goal's value into an incoming-edge environment of
    /// block `bi`. The value is defined above `bi`, so it is the same on every iteration:
    /// a lower bound that holds at the use holds on the edge that fed the use.
    fn carry_goal_facts(&self, goal: Goal, bi: usize, env: &Env, edge: &mut Env) {
        for (&v, i) in &env.itv {
            if !self.goal_matches(v, goal) {
                continue;
            }
            let def_block = match (self.defs[v.index()], self.param_of[v.index()]) {
                (Some((b, _)), _) | (None, Some((b, _))) => b,
                _ => continue,
            };
            let mut b = bi;
            while b != def_block && b != 0 {
                b = self.idom[b];
            }
            if b == def_block {
                edge.narrow(v, i.lo as i128, i.hi as i128);
            }
        }
    }

    /// `u * c <= goal + d` from `u < goal / c` (or `<=`): `(goal / c) * c <= goal` for `goal >= 0`.
    pub(super) fn prove_scaled(&self, def: &Inst, goal: Goal, d: i128, env: &Env) -> bool {
        let (u, c) = match (self.constant(def.args[1]), self.constant(def.args[0])) {
            (Some(c), _) => (def.args[0], c),
            (None, Some(c)) => (def.args[1], c),
            _ => return false,
        };
        if c < 1 {
            return false;
        }
        for &(a, b, strict) in &env.rels {
            if !self.same_value(a, u) {
                continue;
            }
            let Some(q) = self.def_inst(b) else { continue };
            if !matches!(q.op, Op::SDiv | Op::SDivChk) || self.constant(q.args[1]) != Some(c) {
                continue;
            }
            let x = q.args[0];
            let same = match goal {
                Goal::Val(t) => x == t,
                Goal::Len(o) => self.lenof.get(&x) == Some(&o),
            };
            if same
                && self.get(x, env).is_some_and(|i| i.lo >= 0)
                && -(strict as i128) * c as i128 <= d
            {
                return true;
            }
        }
        false
    }

    pub(super) fn edits(&self) -> Vec<Edit> {
        let mut out = Vec::new();
        let f = self.f;
        for &b in &self.rpo {
            let bi = b.index();
            let env = &self.envs[bi];
            for (ii, inst) in f.blocks[bi].insts.iter().enumerate() {
                let get = |k: usize| self.get(inst.args[k], env);
                match inst.op {
                    Op::ListLen => {
                        if let Some(n) = self.list_length(inst.args[0]) {
                            out.push(Edit::Int(bi, ii, n));
                        }
                    }
                    Op::IAddChk | Op::ISubChk | Op::IMulChk => {
                        let (Some(x), Some(y)) = (get(0), get(1)) else {
                            continue;
                        };
                        let (lo, hi) = match inst.op {
                            Op::IAddChk => {
                                (x.lo as i128 + y.lo as i128, x.hi as i128 + y.hi as i128)
                            }
                            Op::ISubChk => {
                                (x.lo as i128 - y.hi as i128, x.hi as i128 - y.lo as i128)
                            }
                            _ => corners(|a, b| a * b, x, y),
                        };
                        if fits(lo, hi) {
                            let op = match inst.op {
                                Op::IAddChk => Op::IAdd,
                                Op::ISubChk => Op::ISub,
                                _ => Op::IMul,
                            };
                            out.push(Edit::Op(bi, ii, op));
                        }
                    }
                    Op::UAddChk | Op::USubChk | Op::UMulChk => {
                        let (Some(x), Some(y)) = (get(0), get(1)) else {
                            continue;
                        };
                        if x.lo < 0 || y.lo < 0 {
                            continue;
                        }
                        let (safe, op) = match inst.op {
                            Op::UAddChk => (
                                fits(x.lo as i128 + y.lo as i128, x.hi as i128 + y.hi as i128),
                                Op::IAdd,
                            ),
                            Op::USubChk => (x.lo >= y.hi, Op::ISub),
                            _ => {
                                let (lo, hi) = corners(|a, b| a * b, x, y);
                                (fits(lo, hi), Op::IMul)
                            }
                        };
                        if safe {
                            out.push(Edit::Op(bi, ii, op));
                        }
                    }
                    Op::IAddOverflow | Op::IMulOverflow => {
                        let (Some(x), Some(y)) = (get(0), get(1)) else {
                            continue;
                        };
                        let (lo, hi) = if inst.op == Op::IAddOverflow {
                            (x.lo as i128 + y.lo as i128, x.hi as i128 + y.hi as i128)
                        } else {
                            corners(|a, b| a * b, x, y)
                        };
                        if fits(lo, hi) {
                            out.push(Edit::Const(bi, ii, false));
                        }
                    }
                    Op::INegChk => {
                        if get(0).is_some_and(|x| x.lo != i64::MIN) {
                            out.push(Edit::Op(bi, ii, Op::INeg));
                        }
                    }
                    Op::SDivChk | Op::SRemChk => {
                        let (Some(x), Some(y)) = (get(0), get(1)) else {
                            continue;
                        };
                        let nonzero = y.lo > 0 || y.hi < 0;
                        let minus_one = y.lo <= -1 && -1 <= y.hi;
                        if nonzero && (!minus_one || x.lo > i64::MIN) {
                            let op = if inst.op == Op::SDivChk {
                                Op::SDiv
                            } else {
                                Op::SRem
                            };
                            out.push(Edit::Op(bi, ii, op));
                        }
                    }
                    Op::ListGet | Op::ListGetNn | Op::ListSet | Op::ListSetNn => {
                        if get(1).is_none() {
                            continue;
                        }
                        let nonneg = self.nonneg(inst.args[1], env);
                        let inside = nonneg && self.below_len(inst.args[1], inst.args[0], env);
                        let set = matches!(inst.op, Op::ListSet | Op::ListSetNn);
                        let target = if inside {
                            Some(if set { Op::ListSetU } else { Op::ListGetU })
                        } else if nonneg && matches!(inst.op, Op::ListGet | Op::ListSet) {
                            Some(if set { Op::ListSetNn } else { Op::ListGetNn })
                        } else {
                            None
                        };
                        if let Some(op) = target {
                            out.push(Edit::Op(bi, ii, op));
                        }
                    }
                    Op::ListAddr => {
                        if self.get(inst.args[1], env).is_none() {
                            continue;
                        }
                        if self.nonneg(inst.args[1], env)
                            && self.below_len(inst.args[1], inst.args[0], env)
                        {
                            out.push(Edit::Op(bi, ii, Op::ListAddrU));
                        }
                    }
                    Op::ICmp => {
                        let decided = inst
                            .res
                            .and_then(|r| self.base[r.index()])
                            .filter(|r| r.is_point());
                        if let Some(r) = decided {
                            out.push(Edit::Const(bi, ii, r.lo != 0));
                        }
                    }
                    _ => {}
                }
            }
            if let Some(t) = self.fold_term(&f.blocks[bi].term, env) {
                out.push(Edit::Term(bi, t));
            }
        }
        out
    }

    pub(super) fn fold_term(&self, term: &Term, env: &Env) -> Option<Term> {
        match term {
            Term::CondBr { cond, then, els } => {
                let c = self.get(*cond, env)?;
                if !c.is_point() {
                    return None;
                }
                Some(Term::Br(if c.lo != 0 { then.clone() } else { els.clone() }))
            }
            Term::Switch {
                value,
                cases,
                default,
            } => {
                let v = self.get(*value, env)?;
                if v.is_point() {
                    let t = cases
                        .iter()
                        .find(|(k, _)| *k == v.lo)
                        .map_or(default, |(_, t)| t);
                    return Some(Term::Br(t.clone()));
                }
                let kept: Vec<(i64, Target)> = cases
                    .iter()
                    .filter(|(k, _)| v.lo <= *k && *k <= v.hi)
                    .cloned()
                    .collect();
                if kept.len() == cases.len() {
                    return None;
                }
                Some(if kept.is_empty() {
                    Term::Br(default.clone())
                } else {
                    Term::Switch {
                        value: *value,
                        cases: kept,
                        default: default.clone(),
                    }
                })
            }
            _ => None,
        }
    }
}
