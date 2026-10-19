//! Type checking and the value-semantics ownership rules:
//! - values have one owner; a droppable value moves out of a local at a
//!   consuming position (binding, assignment, construction, append, return)
//!   and the local cannot be used again until reassigned;
//! - parameters and match bindings borrow, so they cannot be moved out of;
//!   neither can a field or list element (the fix would be `.copy()`);
//! - only `mut` bindings and `mut` parameters can change, and a `mut`
//!   argument is marked at the call site and may not overlap another argument.

use crate::syntax::{error, Arm, BinOp, Block, Error, Expr, ExprKind, FnDecl, Program, StmtKind, TypeDecl, TypeExpr, UnOp};
use crate::types::{AltDef, CaseDef, RecordDef, Ty, Types};
use std::collections::{HashMap, HashSet};

pub struct FnSig {
    pub params: Vec<(Ty, bool)>,
    pub ret: Ty,
}

#[derive(Debug, Clone, Copy)]
pub enum Res {
    Fn(usize),
    Record(usize),
    Case(usize, usize),
    NowUs,
    Report,
    Local,
}

pub struct Checked {
    pub types: Types,
    pub sigs: Vec<FnSig>,
    pub expr_ty: Vec<Ty>,
    pub res: HashMap<usize, Res>,
    /// `Name` expressions that move a droppable value out of their local.
    pub moves: HashSet<usize>,
}

#[derive(Clone)]
struct Local {
    ty: Ty,
    mutable: bool,
    owned: bool,
}

struct Checker<'p> {
    prog: &'p Program,
    out: Checked,
    fn_index: HashMap<String, usize>,
    record_index: HashMap<String, usize>,
    alt_index: HashMap<String, usize>,
    case_index: HashMap<String, (usize, usize)>,
    scopes: Vec<HashMap<String, Local>>,
    ret: Ty,
}

pub fn check(prog: &Program) -> Result<Checked, Error> {
    let mut c = Checker {
        prog,
        out: Checked {
            types: Types::default(),
            sigs: Vec::new(),
            expr_ty: vec![Ty::Unit; prog.expr_count],
            res: HashMap::new(),
            moves: HashSet::new(),
        },
        fn_index: HashMap::new(),
        record_index: HashMap::new(),
        alt_index: HashMap::new(),
        case_index: HashMap::new(),
        scopes: Vec::new(),
        ret: Ty::Unit,
    };
    c.declare()?;
    for f in &prog.fns {
        c.function(f)?;
    }
    for f in &prog.fns {
        let mut moved = HashSet::new();
        c.moves_block(&f.body, &mut moved)?;
    }
    Ok(c.out)
}

fn is_numeric(ty: &Ty) -> bool {
    matches!(ty, Ty::Int | Ty::Float)
}

impl<'p> Checker<'p> {
    fn declare(&mut self) -> Result<(), Error> {
        for decl in &self.prog.types {
            match decl {
                TypeDecl::Record { name, .. } => {
                    self.record_index.insert(name.clone(), self.out.types.records.len());
                    self.out.types.records.push(RecordDef { name: name.clone(), fields: Vec::new() });
                }
                TypeDecl::Alternatives { name, cases } => {
                    let a = self.out.types.alts.len();
                    self.alt_index.insert(name.clone(), a);
                    for (i, case) in cases.iter().enumerate() {
                        self.case_index.insert(case.name.clone(), (a, i));
                    }
                    self.out.types.alts.push(AltDef { name: name.clone(), cases: Vec::new() });
                }
            }
        }
        for decl in &self.prog.types {
            match decl {
                TypeDecl::Record { name, fields } => {
                    let r = self.record_index[name];
                    let fields = fields.iter().map(|f| Ok((f.name.clone(), self.ty(&f.ty)?))).collect::<Result<_, Error>>()?;
                    self.out.types.records[r].fields = fields;
                }
                TypeDecl::Alternatives { name, cases } => {
                    let a = self.alt_index[name];
                    for case in cases {
                        let fields = case.fields.iter().map(|f| Ok((f.name.clone(), self.ty(&f.ty)?))).collect::<Result<_, Error>>()?;
                        self.out.types.alts[a].cases.push(CaseDef { name: case.name.clone(), fields });
                    }
                }
            }
        }
        for (i, f) in self.prog.fns.iter().enumerate() {
            if self.fn_index.insert(f.name.clone(), i).is_some() {
                return error(f.line, format!("`{}` is declared twice", f.name));
            }
            let params = f.params.iter().map(|p| Ok((self.ty(&p.ty)?, p.mutable))).collect::<Result<_, Error>>()?;
            let ret = self.ty(&f.ret)?;
            self.out.sigs.push(FnSig { params, ret });
        }
        if !self.fn_index.contains_key("main") {
            return error(1, "no `main` function");
        }
        Ok(())
    }

    fn ty(&self, t: &TypeExpr) -> Result<Ty, Error> {
        let arity = |n: usize| if t.args.len() == n { Ok(()) } else { error(t.line, format!("`{}` takes {n} type arguments", t.name)) };
        Ok(match t.name.as_str() {
            "Int" => Ty::Int,
            "Float" => Ty::Float,
            "Bool" => Ty::Bool,
            "String" => Ty::Str,
            "Unit" => Ty::Unit,
            "List" => {
                arity(1)?;
                Ty::List(Box::new(self.ty(&t.args[0])?))
            }
            "Map" => {
                arity(2)?;
                if self.ty(&t.args[0])? != Ty::Int || self.ty(&t.args[1])? != Ty::Int {
                    return error(t.line, "the spike supports only Map[Int, Int]");
                }
                Ty::Map
            }
            name => {
                if let Some(&r) = self.record_index.get(name) {
                    Ty::Record(r)
                } else if let Some(&a) = self.alt_index.get(name) {
                    Ty::Alt(a)
                } else {
                    return error(t.line, format!("unknown type `{name}`"));
                }
            }
        })
    }

    fn lookup(&self, name: &str) -> Option<&Local> {
        self.scopes.iter().rev().find_map(|s| s.get(name))
    }

    fn bind(&mut self, name: &str, local: Local) {
        self.scopes.last_mut().unwrap().insert(name.to_string(), local);
    }

    fn function(&mut self, f: &FnDecl) -> Result<(), Error> {
        let sig = &self.out.sigs[self.fn_index[&f.name]];
        self.ret = sig.ret.clone();
        let params: Vec<_> = sig.params.clone();
        self.scopes = vec![HashMap::new()];
        for (p, (ty, mutable)) in f.params.iter().zip(params) {
            self.bind(&p.name, Local { ty, mutable, owned: false });
        }
        self.block(&f.body)?;
        if self.ret != Ty::Unit && !always_returns(&f.body) {
            return error(f.line, format!("`{}` can finish without returning a value", f.name));
        }
        Ok(())
    }

    fn block(&mut self, block: &Block) -> Result<(), Error> {
        self.scopes.push(HashMap::new());
        for s in block {
            self.stmt(&s.kind, s.line)?;
        }
        self.scopes.pop();
        Ok(())
    }

    fn stmt(&mut self, kind: &StmtKind, line: usize) -> Result<(), Error> {
        match kind {
            StmtKind::Let { name, mutable, ty, init } => {
                let got = self.expr(init)?;
                if let Some(t) = ty {
                    let want = self.ty(t)?;
                    if want != got {
                        return error(line, format!("`{name}` is declared {} but initialized with {}", self.name(&want), self.name(&got)));
                    }
                }
                self.consume(init, &got)?;
                self.bind(name, Local { ty: got, mutable: *mutable, owned: true });
            }
            StmtKind::Assign { target, op, value } => {
                let target_ty = self.expr(target)?;
                self.mutable_place(target)?;
                let value_ty = self.expr(value)?;
                if target_ty != value_ty {
                    return error(line, format!("cannot assign {} to {}", self.name(&value_ty), self.name(&target_ty)));
                }
                match op {
                    Some(_) if !is_numeric(&target_ty) => return error(line, "compound assignment needs Int or Float"),
                    Some(BinOp::Div) if target_ty == Ty::Int => {}
                    Some(_) => {}
                    None => self.consume(value, &value_ty)?,
                }
            }
            StmtKind::While { cond, body } => {
                self.condition(cond)?;
                self.block(body)?;
            }
            StmtKind::If { cond, then, els } => {
                self.condition(cond)?;
                self.block(then)?;
                if let Some(els) = els {
                    self.block(els)?;
                }
            }
            StmtKind::Return(value) => {
                let got = self.expr(value)?;
                if got != self.ret {
                    return error(line, format!("returns {} but the function returns {}", self.name(&got), self.name(&self.ret)));
                }
                self.consume(value, &got)?;
            }
            StmtKind::Match { scrutinee, arms } => self.match_stmt(scrutinee, arms, line)?,
            StmtKind::Expr(e) => {
                self.expr(e)?;
            }
        }
        Ok(())
    }

    fn match_stmt(&mut self, scrutinee: &Expr, arms: &[Arm], line: usize) -> Result<(), Error> {
        let Ty::Alt(a) = self.expr(scrutinee)? else {
            return error(line, "match needs a value with alternatives");
        };
        let mut seen = HashSet::new();
        for arm in arms {
            let Some(&(alt, case)) = self.case_index.get(&arm.case) else {
                return error(arm.line, format!("unknown case `{}`", arm.case));
            };
            if alt != a || !seen.insert(case) {
                return error(arm.line, format!("case `{}` does not belong here or repeats", arm.case));
            }
            let fields: Vec<Ty> = self.out.types.alts[a].cases[case].fields.iter().map(|(_, t)| t.clone()).collect();
            if fields.len() != arm.binds.len() {
                return error(arm.line, format!("`{}` has {} fields", arm.case, fields.len()));
            }
            self.scopes.push(HashMap::new());
            for (name, ty) in arm.binds.iter().zip(fields) {
                self.bind(name, Local { ty, mutable: false, owned: false });
            }
            self.block(&arm.body)?;
            self.scopes.pop();
        }
        if seen.len() != self.out.types.alts[a].cases.len() {
            return error(line, "match does not cover every case");
        }
        Ok(())
    }

    fn condition(&mut self, cond: &Expr) -> Result<(), Error> {
        if self.expr(cond)? != Ty::Bool {
            return error(cond.line, "condition must be Bool");
        }
        Ok(())
    }

    fn name(&self, ty: &Ty) -> String {
        self.out.types.name(ty)
    }

    /// A droppable value at a consuming position must be owned: a fresh value
    /// or an owned local, which then moves.
    fn consume(&mut self, e: &Expr, ty: &Ty) -> Result<(), Error> {
        if !self.out.types.needs_drop(ty) {
            return Ok(());
        }
        match &e.kind {
            ExprKind::Name(name) => {
                let local = self.lookup(name).cloned();
                match local {
                    Some(l) if l.owned => {
                        self.out.moves.insert(e.id);
                        Ok(())
                    }
                    Some(_) => error(e.line, format!("`{name}` is borrowed and cannot be moved; copy it with `.copy()`")),
                    None => Ok(()),
                }
            }
            ExprKind::Field(..) | ExprKind::Index(..) => {
                error(e.line, "cannot move a value out of a field or element; copy it with `.copy()`")
            }
            _ => Ok(()),
        }
    }

    /// Assignment targets and `mut` arguments: a place rooted at a `mut` binding.
    fn mutable_place(&self, e: &Expr) -> Result<String, Error> {
        match &e.kind {
            ExprKind::Name(name) => match self.lookup(name) {
                Some(l) if l.mutable => Ok(name.clone()),
                Some(_) => error(e.line, format!("`{name}` is not `mut`")),
                None => error(e.line, format!("`{name}` is not a variable")),
            },
            ExprKind::Field(base, _) | ExprKind::Index(base, _) => self.mutable_place(base),
            _ => error(e.line, "only variables, fields, and list elements can be changed"),
        }
    }

    fn expr(&mut self, e: &Expr) -> Result<Ty, Error> {
        let ty = self.expr_inner(e)?;
        self.out.expr_ty[e.id] = ty.clone();
        Ok(ty)
    }

    fn expr_inner(&mut self, e: &Expr) -> Result<Ty, Error> {
        Ok(match &e.kind {
            ExprKind::Int(_) => Ty::Int,
            ExprKind::Float(_) => Ty::Float,
            ExprKind::Bool(_) => Ty::Bool,
            ExprKind::Str(_) => Ty::Str,
            ExprKind::Name(name) => {
                if let Some(ty) = self.lookup(name).map(|l| l.ty.clone()) {
                    self.out.res.insert(e.id, Res::Local);
                    return Ok(ty);
                }
                if let Some(&(a, c)) = self.case_index.get(name) {
                    if self.out.types.alts[a].cases[c].fields.is_empty() {
                        self.out.res.insert(e.id, Res::Case(a, c));
                        return Ok(Ty::Alt(a));
                    }
                }
                return error(e.line, format!("unknown name `{name}`"));
            }
            ExprKind::Unary(op, x) => {
                let t = self.expr(x)?;
                match (op, &t) {
                    (UnOp::Not, Ty::Bool) | (UnOp::Neg, Ty::Int | Ty::Float) => t,
                    _ => return error(e.line, format!("invalid operand {}", self.name(&t))),
                }
            }
            ExprKind::Binary(op, l, r) => {
                let lt = self.expr(l)?;
                let rt = self.expr(r)?;
                if lt != rt {
                    return error(e.line, format!("operands differ: {} and {}", self.name(&lt), self.name(&rt)));
                }
                match op {
                    BinOp::And | BinOp::Or if lt == Ty::Bool => Ty::Bool,
                    BinOp::Eq | BinOp::Ne if matches!(lt, Ty::Int | Ty::Float | Ty::Bool) => Ty::Bool,
                    BinOp::Lt | BinOp::Le | BinOp::Gt | BinOp::Ge if is_numeric(&lt) => Ty::Bool,
                    BinOp::Mod if lt == Ty::Int => Ty::Int,
                    BinOp::Add | BinOp::Sub | BinOp::Mul | BinOp::Div if is_numeric(&lt) => lt,
                    _ => return error(e.line, format!("invalid operands {}", self.name(&lt))),
                }
            }
            ExprKind::Call { callee, args } => self.call(e, callee, args)?,
            ExprKind::Method { recv, name, args } => self.method(e, recv, name, args)?,
            ExprKind::Field(base, field) => {
                let Ty::Record(r) = self.expr(base)? else {
                    return error(e.line, format!("`.{field}` needs a record"));
                };
                let rec = &self.out.types.records[r];
                let Some((_, t)) = rec.fields.iter().find(|(n, _)| n == field) else {
                    return error(e.line, format!("`{}` has no field `{field}`", rec.name));
                };
                t.clone()
            }
            ExprKind::Index(base, index) => {
                let Ty::List(elem) = self.expr(base)? else {
                    return error(e.line, "indexing needs a List");
                };
                if self.expr(index)? != Ty::Int {
                    return error(e.line, "index must be Int");
                }
                *elem
            }
            ExprKind::New(t) => self.ty(t)?,
        })
    }

    fn call(&mut self, e: &Expr, callee: &str, args: &[crate::syntax::Arg]) -> Result<Ty, Error> {
        let mut tys = Vec::new();
        for a in args {
            tys.push(self.expr(&a.expr)?);
        }
        let expect = |want: &[Ty], tys: &[Ty]| -> Result<(), Error> {
            if want != tys {
                return error(e.line, format!("wrong arguments to `{callee}`"));
            }
            Ok(())
        };
        if let Some(&f) = self.fn_index.get(callee) {
            self.out.res.insert(e.id, Res::Fn(f));
            let params = &self.out.sigs[f].params;
            let want: Vec<Ty> = params.iter().map(|(t, _)| t.clone()).collect();
            let flags: Vec<bool> = params.iter().map(|(_, m)| *m).collect();
            let ret = self.out.sigs[f].ret.clone();
            expect(&want, &tys)?;
            let mut roots = Vec::new();
            for (a, m) in args.iter().zip(&flags) {
                if a.mutable != *m {
                    let fix = if *m { "add `mut` at the call" } else { "remove `mut`" };
                    return error(a.expr.line, format!("argument mutability differs from `{callee}`: {fix}"));
                }
                if *m {
                    roots.push(self.mutable_place(&a.expr)?);
                }
            }
            for root in &roots {
                let uses = args.iter().filter(|a| mentions(&a.expr, root)).count();
                if uses > 1 {
                    return error(e.line, format!("`mut {root}` overlaps another argument"));
                }
            }
            return Ok(ret);
        }
        if let Some(&r) = self.record_index.get(callee) {
            self.out.res.insert(e.id, Res::Record(r));
            let want: Vec<Ty> = self.out.types.records[r].fields.iter().map(|(_, t)| t.clone()).collect();
            expect(&want, &tys)?;
            for (a, t) in args.iter().zip(&tys) {
                self.consume(&a.expr, t)?;
            }
            return Ok(Ty::Record(r));
        }
        if let Some(&(a, c)) = self.case_index.get(callee) {
            self.out.res.insert(e.id, Res::Case(a, c));
            let want: Vec<Ty> = self.out.types.alts[a].cases[c].fields.iter().map(|(_, t)| t.clone()).collect();
            expect(&want, &tys)?;
            for (arg, t) in args.iter().zip(&tys) {
                self.consume(&arg.expr, t)?;
            }
            return Ok(Ty::Alt(a));
        }
        match callee {
            "now_us" => {
                expect(&[], &tys)?;
                self.out.res.insert(e.id, Res::NowUs);
                Ok(Ty::Int)
            }
            "report" => {
                expect(&[Ty::Str, Ty::Int, Ty::Int], &tys)?;
                self.out.res.insert(e.id, Res::Report);
                Ok(Ty::Unit)
            }
            _ => error(e.line, format!("unknown function `{callee}`")),
        }
    }

    fn method(&mut self, e: &Expr, recv: &Expr, name: &str, args: &[Expr]) -> Result<Ty, Error> {
        let rt = self.expr(recv)?;
        let mut tys = Vec::new();
        for a in args {
            tys.push(self.expr(a)?);
        }
        let sig: (&[Ty], Ty, bool) = match (&rt, name) {
            (Ty::List(elem), "append") => (std::slice::from_ref(&**elem), Ty::Unit, true),
            (Ty::List(_), "length") | (Ty::Map, "length") => (&[], Ty::Int, false),
            (Ty::Map, "add") => (&[Ty::Int, Ty::Int], Ty::Unit, true),
            (Ty::Map, "get") => (&[Ty::Int], Ty::OptInt, false),
            (Ty::OptInt, "get") => (&[Ty::Int], Ty::Int, false),
            (Ty::Int, "to_float") => (&[], Ty::Float, false),
            (Ty::Float, "truncate_to_int") => (&[], Ty::OptInt, false),
            _ => return error(e.line, format!("{} has no method `{name}`", self.name(&rt))),
        };
        if sig.0 != tys.as_slice() {
            return error(e.line, format!("wrong arguments to `{name}`"));
        }
        if sig.2 {
            self.mutable_place(recv)?;
        }
        if name == "append" {
            self.consume(&args[0], &tys[0])?;
        }
        Ok(sig.1)
    }

    /// Rejects use of a local after its value moved, following control flow.
    fn moves_block(&self, block: &Block, moved: &mut HashSet<String>) -> Result<bool, Error> {
        for s in block {
            let returned = match &s.kind {
                StmtKind::Let { name, init, .. } => {
                    self.moves_expr(init, moved)?;
                    moved.remove(name);
                    false
                }
                StmtKind::Assign { target, op, value } => {
                    self.moves_expr(value, moved)?;
                    match (&target.kind, op) {
                        (ExprKind::Name(name), None) => {
                            moved.remove(name);
                        }
                        _ => self.moves_expr(target, moved)?,
                    }
                    false
                }
                StmtKind::While { cond, body } => {
                    let before = moved.clone();
                    for _ in 0..2 {
                        self.moves_expr(cond, moved)?;
                        self.moves_block(body, moved)?;
                    }
                    moved.extend(before);
                    false
                }
                StmtKind::If { cond, then, els } => {
                    self.moves_expr(cond, moved)?;
                    let mut a = moved.clone();
                    let mut b = moved.clone();
                    let ra = self.moves_block(then, &mut a)?;
                    let rb = match els {
                        Some(els) => self.moves_block(els, &mut b)?,
                        None => false,
                    };
                    moved.clear();
                    if !ra {
                        moved.extend(a);
                    }
                    if !rb {
                        moved.extend(b);
                    }
                    ra && rb
                }
                StmtKind::Return(value) => {
                    self.moves_expr(value, moved)?;
                    true
                }
                StmtKind::Match { scrutinee, arms } => {
                    self.moves_expr(scrutinee, moved)?;
                    let start = moved.clone();
                    moved.clear();
                    let mut all = true;
                    for arm in arms {
                        let mut m = start.clone();
                        if !self.moves_block(&arm.body, &mut m)? {
                            all = false;
                            moved.extend(m);
                        }
                    }
                    all
                }
                StmtKind::Expr(e) => {
                    self.moves_expr(e, moved)?;
                    false
                }
            };
            if returned {
                return Ok(true);
            }
        }
        Ok(false)
    }

    fn moves_expr(&self, e: &Expr, moved: &mut HashSet<String>) -> Result<(), Error> {
        match &e.kind {
            ExprKind::Name(name) => {
                if moved.contains(name) {
                    return error(e.line, format!("`{name}` is used after its value moved"));
                }
                if self.out.moves.contains(&e.id) {
                    moved.insert(name.clone());
                }
            }
            ExprKind::Unary(_, x) | ExprKind::Field(x, _) => self.moves_expr(x, moved)?,
            ExprKind::Binary(_, l, r) | ExprKind::Index(l, r) => {
                self.moves_expr(l, moved)?;
                self.moves_expr(r, moved)?;
            }
            ExprKind::Call { args, .. } => {
                for a in args {
                    self.moves_expr(&a.expr, moved)?;
                }
            }
            ExprKind::Method { recv, args, .. } => {
                self.moves_expr(recv, moved)?;
                for a in args {
                    self.moves_expr(a, moved)?;
                }
            }
            _ => {}
        }
        Ok(())
    }
}

fn mentions(e: &Expr, name: &str) -> bool {
    match &e.kind {
        ExprKind::Name(n) => n == name,
        ExprKind::Unary(_, x) | ExprKind::Field(x, _) => mentions(x, name),
        ExprKind::Binary(_, l, r) | ExprKind::Index(l, r) => mentions(l, name) || mentions(r, name),
        ExprKind::Call { args, .. } => args.iter().any(|a| mentions(&a.expr, name)),
        ExprKind::Method { recv, args, .. } => mentions(recv, name) || args.iter().any(|a| mentions(a, name)),
        _ => false,
    }
}

pub fn always_returns(block: &Block) -> bool {
    block.iter().any(|s| match &s.kind {
        StmtKind::Return(_) => true,
        StmtKind::If { then, els: Some(els), .. } => always_returns(then) && always_returns(els),
        StmtKind::Match { arms, .. } => arms.iter().all(|a| always_returns(&a.body)),
        _ => false,
    })
}
