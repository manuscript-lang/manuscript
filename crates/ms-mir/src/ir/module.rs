//! Module-level construction and queries, and the recursive-layout decisions ([`Boxing`]).

use super::*;

impl Default for Module {
    fn default() -> Self {
        Self::new("module")
    }
}

impl Module {
    /// An empty module.
    pub fn new(name: &str) -> Module {
        Module {
            name: name.to_string(),
            files: Vec::new(),
            types: TyTable::new(),
            type_defs: Vec::new(),
            alts: Vec::new(),
            ifaces: Vec::new(),
            vtables: Vec::new(),
            strings: Vec::new(),
            list_consts: Vec::new(),
            blobs: Vec::new(),
            string_ids: HashMap::new(),
            externs: Vec::new(),
            extern_ids: HashMap::new(),
            globals: Vec::new(),
            funcs: Vec::new(),
            entry: None,
            desc_glue: Vec::new(),
            c_externs: std::collections::BTreeSet::new(),
        }
    }

    /// Interns a string literal.
    pub fn add_string(&mut self, s: &str) -> StrId {
        if let Some(&id) = self.string_ids.get(s) {
            return id;
        }
        let id = StrId(self.strings.len() as u32);
        self.strings.push(s.to_string());
        self.string_ids.insert(s.to_string(), id);
        id
    }

    /// Registers the bytes of a constant `Bytes` and returns its index.
    pub fn add_blob(&mut self, data: Vec<u8>) -> i64 {
        self.blobs.push(data);
        self.blobs.len() as i64 - 1
    }

    /// Registers the element data of a constant list and returns its index.
    pub fn add_list_const(&mut self, data: Vec<i64>) -> i64 {
        self.list_consts.push(data);
        self.list_consts.len() as i64 - 1
    }

    /// Registers a source file and returns its index for [`Loc`].
    pub fn add_file(&mut self, path: &str) -> u32 {
        if let Some(i) = self.files.iter().position(|x| x == path) {
            return i as u32;
        }
        self.files.push(path.to_string());
        self.files.len() as u32 - 1
    }

    /// Declares a type and returns its id and type.
    pub fn add_type(&mut self, name: &str, fields: Vec<(String, Ty)>) -> (TypeId, Ty) {
        self.type_defs.push(TypeDef {
            name: name.to_string(),
            fields,
            native: None,
            indirect: false,
        });
        let id = TypeId(self.type_defs.len() as u32 - 1);
        (id, self.types.named(id))
    }

    /// Declares an alternative and returns its id and type.
    pub fn add_alt(&mut self, name: &str, cases: Vec<crate::types::CaseDef>) -> (AltId, Ty) {
        self.alts.push(AltDef {
            name: name.to_string(),
            std: Default::default(),
            cases,
            borrowed: 0,
        });
        let id = AltId(self.alts.len() as u32 - 1);
        (id, self.types.alt(id))
    }

    /// The borrowing variant of `base` whose cases in `mask` are borrowed from another value: the
    /// same layout and cases, but dropping it leaves those cases alone. Memoized per mask.
    pub fn borrowing_alt(&mut self, base: AltId, mask: u64) -> (AltId, Ty) {
        let def = self.alts[base.index()].clone();
        let mask = mask | def.borrowed;
        if mask == def.borrowed {
            return (base, self.types.alt(base));
        }
        let found = self
            .alts
            .iter()
            .position(|a| a.name == def.name && a.cases == def.cases && a.borrowed == mask);
        let id = match found {
            Some(i) => AltId(i as u32),
            None => {
                self.alts.push(AltDef {
                    borrowed: mask,
                    ..def
                });
                AltId(self.alts.len() as u32 - 1)
            }
        };
        (id, self.types.alt(id))
    }

    /// Declares a runtime function (or returns the existing one with this symbol and signature).
    pub fn add_extern(&mut self, def: ExternDef) -> ExtId {
        let same = |e: &ExternDef| {
            e.ret == def.ret
                && e.params.len() == def.params.len()
                && e.params.iter().zip(&def.params).all(|(a, b)| a.ty == b.ty)
        };
        let found = self.extern_ids.get(&def.name).and_then(|ids| {
            ids.iter()
                .copied()
                .find(|id| same(&self.externs[id.index()]))
        });
        found.unwrap_or_else(|| self.push_extern(def))
    }

    /// Appends a declaration without looking for an existing one.
    pub fn push_extern(&mut self, def: ExternDef) -> ExtId {
        let id = ExtId(self.externs.len() as u32);
        self.extern_ids
            .entry(def.name.clone())
            .or_default()
            .push(id);
        self.externs.push(def);
        id
    }

    /// The first runtime function declared with this symbol.
    pub fn extern_by_name(&self, name: &str) -> Option<ExtId> {
        self.extern_ids
            .get(name)
            .and_then(|ids| ids.first().copied())
    }

    /// Adds a function.
    pub fn add_func(&mut self, f: Func) -> FuncId {
        self.funcs.push(f);
        FuncId(self.funcs.len() as u32 - 1)
    }

    /// Finds a function by name.
    pub fn func_by_name(&self, name: &str) -> Option<FuncId> {
        self.funcs
            .iter()
            .position(|f| f.name == name)
            .map(|i| FuncId(i as u32))
    }

    /// Finds a type by name.
    pub fn type_by_name(&self, name: &str) -> Option<TypeId> {
        self.type_defs
            .iter()
            .position(|r| r.name == name)
            .map(|i| TypeId(i as u32))
    }

    /// Finds an alternative by name.
    pub fn alt_by_name(&self, name: &str) -> Option<AltId> {
        self.alts
            .iter()
            .position(|r| r.name == name)
            .map(|i| AltId(i as u32))
    }

    /// The element type of a list type.
    pub fn list_elem(&self, ty: Ty) -> Option<Ty> {
        match self.types.kind(ty) {
            TyKind::List(e) => Some(*e),
            _ => None,
        }
    }

    /// The element type of a list, or `uint8` for bytes, which share the list layout.
    pub fn seq_elem(&self, ty: Ty) -> Option<Ty> {
        match self.types.kind(ty) {
            TyKind::List(e) => Some(*e),
            TyKind::Bytes => Some(Ty::UINT8),
            _ => None,
        }
    }

    /// The payload type of an optional type.
    pub fn opt_inner(&self, ty: Ty) -> Option<Ty> {
        match self.types.kind(ty) {
            TyKind::Opt(e) => Some(*e),
            _ => None,
        }
    }

    /// The field types of a type or alternative case, for `type.new`/`alt.new`.
    pub fn field_types(&self, imm: Imm) -> Option<Vec<Ty>> {
        match imm {
            Imm::Type(r) => Some(
                self.type_defs
                    .get(r.index())?
                    .fields
                    .iter()
                    .map(|f| f.1)
                    .collect(),
            ),
            Imm::Case(a, c) => Some(
                self.alts
                    .get(a.index())?
                    .cases
                    .get(c as usize)?
                    .fields
                    .iter()
                    .map(|f| f.1)
                    .collect(),
            ),
            _ => None,
        }
    }

    /// Whether `inner?` contains itself by value (`type Node: next: Node?`)
    /// and therefore holds its payload in a heap block behind a nullable pointer. Backends
    /// share this rule through [`Boxing`], which memoizes it.
    pub fn opt_is_boxed(&self, inner: Ty) -> bool {
        Boxing::default().opt(self, inner)
    }

    /// Whether values of `ty` own resources that must be dropped (strings, lists,
    /// maps, closures, interfaces, boxed or recursive alternatives, and types,
    /// alternatives and optionals containing them). Plain data is copied freely.
    pub fn needs_drop(&self, ty: Ty) -> bool {
        self.needs_drop_in(ty, &mut Vec::new())
    }

    fn needs_drop_in(&self, ty: Ty, seen: &mut Vec<Ty>) -> bool {
        match self.types.kind(ty) {
            TyKind::Unit
            | TyKind::Bool
            | TyKind::Int
            | TyKind::Int8
            | TyKind::Int16
            | TyKind::Int32
            | TyKind::UInt8
            | TyKind::UInt16
            | TyKind::UInt32
            | TyKind::UInt64
            | TyKind::Float
            | TyKind::Float32
            | TyKind::Ptr => false,
            TyKind::Opt(inner) => self.needs_drop_in(*inner, seen),
            TyKind::Type(r) => {
                if seen.contains(&ty) {
                    return true;
                }
                seen.push(ty);
                let out = self.type_defs[r.index()]
                    .fields
                    .iter()
                    .any(|f| self.needs_drop_in(f.1, seen));
                seen.pop();
                out
            }
            TyKind::Alt(a) => {
                if seen.contains(&ty) {
                    return true;
                }
                seen.push(ty);
                let def = &self.alts[a.index()];
                let out = def
                    .cases
                    .iter()
                    .enumerate()
                    .filter(|(i, _)| !def.borrows(*i))
                    .any(|(_, c)| c.fields.iter().any(|f| self.needs_drop_in(f.1, seen)));
                seen.pop();
                out
            }
            _ => true,
        }
    }

    /// Whether dropping a value of `ty` can drop a value of `ty` again below it: the type
    /// reaches itself through its fields, cases, optional payloads and collection elements
    /// (`type Json: ... List[Json]`). Its drop glue bounds its own nesting (`ms_rt::dropq`).
    pub fn drop_recurses(&self, ty: Ty) -> bool {
        let mut seen = Vec::new();
        let mut todo = self.drop_children(ty);
        while let Some(t) = todo.pop() {
            if t == ty {
                return true;
            }
            if !seen.contains(&t) {
                seen.push(t);
                todo.extend(self.drop_children(t));
            }
        }
        false
    }

    /// The types whose values a drop of `ty` drops.
    fn drop_children(&self, ty: Ty) -> Vec<Ty> {
        use crate::types::Native;
        match self.types.kind(ty) {
            TyKind::Opt(inner) | TyKind::List(inner) => vec![*inner],
            TyKind::Obj(Native::Map | Native::Set, args) => args.clone(),
            TyKind::Type(r) => self.type_defs[r.index()]
                .fields
                .iter()
                .map(|f| f.1)
                .collect(),
            TyKind::Alt(a) => {
                let def = &self.alts[a.index()];
                (0..def.cases.len())
                    .filter(|i| !def.borrows(*i))
                    .flat_map(|i| def.cases[i].fields.iter().map(|f| f.1))
                    .collect()
            }
            _ => Vec::new(),
        }
    }

    /// Whether dropping a value of `ty` only returns memory: strings, bytes, lists, maps, sets,
    /// big integers, optionals, types and alternatives made of such. A closure, an interface
    /// value or an opaque runtime handle may own a file or a connection, so it is not plain.
    pub fn drops_plain_memory(&self, ty: Ty) -> bool {
        self.drops_plain_in(ty, &mut Vec::new())
    }

    fn drops_plain_in(&self, ty: Ty, seen: &mut Vec<Ty>) -> bool {
        use crate::types::Native;
        if seen.contains(&ty) {
            return true;
        }
        match self.types.kind(ty) {
            TyKind::Fn(..) | TyKind::Iface(_) => false,
            TyKind::Obj(Native::Map | Native::Set | Native::BigInt, args) => {
                seen.push(ty);
                let out = args.iter().all(|a| self.drops_plain_in(*a, seen));
                seen.pop();
                out
            }
            TyKind::Obj(..) => false,
            TyKind::List(inner) | TyKind::Opt(inner) => {
                seen.push(ty);
                let out = self.drops_plain_in(*inner, seen);
                seen.pop();
                out
            }
            TyKind::Type(r) => {
                seen.push(ty);
                let out = self.type_defs[r.index()]
                    .fields
                    .iter()
                    .all(|f| self.drops_plain_in(f.1, seen));
                seen.pop();
                out
            }
            TyKind::Alt(a) => {
                seen.push(ty);
                let def = &self.alts[a.index()];
                let out = def
                    .cases
                    .iter()
                    .all(|c| c.fields.iter().all(|f| self.drops_plain_in(f.1, seen)));
                seen.pop();
                out
            }
            _ => true,
        }
    }

    /// The ownership mode of the result of `inst` in `f`, if it is an owned value.
    pub fn result_mode(&self, f: &Func, inst: &Inst) -> Option<Mode> {
        let res = inst.res?;
        if !self.needs_drop(f.ty(res)) {
            return None;
        }
        Some(match inst.op {
            Op::TypeGet
            | Op::AltGet
            | Op::ListGet
            | Op::ListGetNn
            | Op::ListGetU
            | Op::OptGet
            | Op::ClosureCap
            | Op::GlobalGet
            | Op::Load
            | Op::StrLit
            | Op::BytesLit
            | Op::StrAscii
            | Op::OptView
            | Op::AltPlain
            | Op::OptNone => Mode::Borrow,
            // A borrowing variant is owned and drops only the cases it owns: `alt.view` fills a
            // borrowed case and is a borrow in an ordinary alternative.
            Op::AltView => match self.types.kind(f.ty(res)) {
                TyKind::Alt(a) if self.alts[a.index()].borrowed != 0 => Mode::Move,
                _ => Mode::Borrow,
            },
            // A borrow-returning function hands back a reference into its arguments.
            Op::Call if matches!(inst.imm, Imm::Func(g) if self.funcs[g.index()].ret_borrowed) => {
                Mode::Borrow
            }
            _ => Mode::Move,
        })
    }

    /// Whether `inst`'s owned result points into its operands: an interface view (`iface.borrow`,
    /// `iface.view`) or a call to a view returner. Passes that move drops or elide copies treat
    /// the result as a borrow of the operands and never move it into an owning position.
    pub fn result_views(&self, f: &Func, inst: &Inst) -> bool {
        match inst.op {
            Op::IfaceBorrow | Op::IfaceView => true,
            Op::Call if matches!(inst.imm, Imm::Func(g) if self.funcs[g.index()].ret_view) => true,
            Op::CallRt
                if matches!(inst.imm, Imm::Ext(e)
                    if self.externs[e.index()].role == ExternRole::ViewResult) =>
            {
                true
            }
            // A borrowing variant (a `Result` that borrows some cases from its arguments and
            // owns the others) points into the arguments the borrowed cases came from.
            Op::AltView | Op::Call | Op::CallInd | Op::CallMethod => inst.res.is_some_and(|r| {
                matches!(self.types.kind(f.ty(r)),
                        TyKind::Alt(a) if self.alts[a.index()].borrowed != 0)
            }),
            _ => false,
        }
    }
}

/// The recursive-layout decisions of a module: an alternative or an optional that contains
/// itself by value lives behind a pointer. One `Boxing` memoizes the answers for a module.
#[derive(Default)]
pub struct Boxing {
    alts: HashMap<AltId, bool>,
    opts: HashMap<Ty, bool>,
}

impl Boxing {
    /// Whether the alternative contains itself by value and therefore lives behind a pointer.
    pub fn alt(&mut self, m: &Module, a: AltId) -> bool {
        if let Some(b) = self.alts.get(&a) {
            return *b;
        }
        // Provisional answer for cycles through other alternatives.
        self.alts.insert(a, false);
        let target = m.types.find(&TyKind::Alt(a));
        let b = target.is_some_and(|t| self.reaches_by_value(m, t, t, &mut Vec::new()));
        self.alts.insert(a, b);
        b
    }

    /// Whether `inner?` contains itself by value.
    pub fn opt(&mut self, m: &Module, inner: Ty) -> bool {
        if let Some(b) = self.opts.get(&inner) {
            return *b;
        }
        self.opts.insert(inner, false);
        let target = m.types.find(&TyKind::Opt(inner));
        let b = target.is_some_and(|t| self.reaches_by_value(m, t, t, &mut Vec::new()));
        self.opts.insert(inner, b);
        b
    }

    fn reaches_by_value(&mut self, m: &Module, from: Ty, target: Ty, seen: &mut Vec<Ty>) -> bool {
        let children: Vec<Ty> = match m.types.kind(from) {
            TyKind::Type(r) => m.type_defs[r.index()].fields.iter().map(|f| f.1).collect(),
            TyKind::Alt(a) => m.alts[a.index()]
                .cases
                .iter()
                .flat_map(|c| c.fields.iter().map(|f| f.1))
                .collect(),
            TyKind::Opt(t) => vec![*t],
            _ => return false,
        };
        for c in children {
            if c == target {
                return true;
            }
            if seen.contains(&c) {
                continue;
            }
            seen.push(c);
            // Stop at other boxed alternatives and optionals: they are one pointer.
            if let TyKind::Alt(a) = m.types.kind(c)
                && self.alt(m, *a)
            {
                continue;
            }
            if let TyKind::Opt(i) = m.types.kind(c)
                && self.opt(m, *i)
            {
                continue;
            }
            if self.reaches_by_value(m, c, target, seen) {
                return true;
            }
        }
        false
    }
}
