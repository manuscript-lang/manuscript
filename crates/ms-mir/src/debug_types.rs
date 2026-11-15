//! Source-level descriptions of the module's types for debug information.
//!
//! Both backends turn the same [`DebugType`] list into their debug format (DWARF DIEs for
//! Cranelift, `!DI*` metadata for LLVM), so what a debugger shows for a `String`, a list, a map, a
//! record, an enum or an optional is decided once, from the machine layout the code generators
//! share ([`Layouts`]). Entries refer to each other by index and may be cyclic (a node pointing
//! to itself).

use crate::ir::Module;
use crate::layout::{AltRepr, Layouts, Leaf, mem_layout};
use crate::types::{AltId, Ty, TyKind, TypeId};
use std::collections::HashMap;

/// How a base type is encoded.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Encoding {
    Bool,
    Signed,
    Unsigned,
    Float,
}

/// A member of a struct or union.
#[derive(Clone, PartialEq, Eq, Debug)]
pub struct Member {
    pub name: String,
    /// Byte offset from the start of the value.
    pub offset: u32,
    /// Index into the list.
    pub ty: usize,
}

/// What a type is.
#[derive(Clone, PartialEq, Eq, Debug)]
pub enum DebugKind {
    Base(Encoding),
    Struct(Vec<Member>),
    Union(Vec<Member>),
    /// A pointer to the indexed type; `None` is a pointer to unknown data.
    Pointer(Option<usize>),
}

/// One type.
#[derive(Clone, PartialEq, Eq, Debug)]
pub struct DebugType {
    /// The name a debugger shows and a pretty-printer matches: `String`, `List[Int]`, `Point`.
    pub name: String,
    /// Size in bytes.
    pub size: u32,
    pub kind: DebugKind,
}

/// Describes every type the module declares or uses, once each.
pub fn debug_types(m: &Module) -> Vec<DebugType> {
    debug_types_by_ty(m).0
}

/// [`debug_types`], and the list index of each MIR type (indexed by `Ty`).
pub fn debug_types_by_ty(m: &Module) -> (Vec<DebugType>, Vec<usize>) {
    let mut b = Builder {
        m,
        layouts: Layouts::new(m),
        out: Vec::new(),
        ids: HashMap::new(),
        leaves: HashMap::new(),
    };
    let of_ty = (0..m.types.len()).map(|i| b.ty(Ty(i as u32))).collect();
    (b.out, of_ty)
}

struct Builder<'m> {
    m: &'m Module,
    layouts: Layouts<'m>,
    out: Vec<DebugType>,
    ids: HashMap<Ty, usize>,
    leaves: HashMap<Leaf, usize>,
}

impl Builder<'_> {
    fn push(&mut self, name: String, size: u32, kind: DebugKind) -> usize {
        self.out.push(DebugType { name, size, kind });
        self.out.len() - 1
    }

    /// The base type of one machine leaf.
    fn leaf(&mut self, leaf: Leaf) -> usize {
        if let Some(&i) = self.leaves.get(&leaf) {
            return i;
        }
        let (name, enc) = match leaf {
            Leaf::I64 => ("UInt64", Encoding::Unsigned),
            Leaf::F64 => ("Float", Encoding::Float),
            Leaf::I8 => ("Bool", Encoding::Bool),
            Leaf::N8 => ("Int8", Encoding::Signed),
            Leaf::N16 => ("Int16", Encoding::Signed),
            Leaf::N32 => ("Int32", Encoding::Signed),
            Leaf::U8 => ("UInt8", Encoding::Unsigned),
            Leaf::U16 => ("UInt16", Encoding::Unsigned),
            Leaf::U32 => ("UInt32", Encoding::Unsigned),
            Leaf::F32 => ("Float32", Encoding::Float),
        };
        let i = self.push(name.into(), leaf.size(), DebugKind::Base(enc));
        self.leaves.insert(leaf, i);
        i
    }

    fn name(&self, ty: Ty) -> String {
        let list = |tys: &[Ty]| {
            tys.iter()
                .map(|t| self.name(*t))
                .collect::<Vec<_>>()
                .join(", ")
        };
        match self.m.types.kind(ty) {
            TyKind::Unit => "Unit".into(),
            TyKind::Bool => "Bool".into(),
            TyKind::Int => "Int".into(),
            TyKind::Float => "Float".into(),
            TyKind::Int8 => "Int8".into(),
            TyKind::Int16 => "Int16".into(),
            TyKind::Int32 => "Int32".into(),
            TyKind::Float32 => "Float32".into(),
            TyKind::UInt8 => "UInt8".into(),
            TyKind::UInt16 => "UInt16".into(),
            TyKind::UInt32 => "UInt32".into(),
            TyKind::UInt64 => "UInt64".into(),
            TyKind::Str => "String".into(),
            TyKind::Bytes => "Bytes".into(),
            TyKind::Ptr => "Ptr".into(),
            TyKind::Type(r) => self.m.type_defs[r.index()].name.clone(),
            TyKind::Alt(a) => self.m.alts[a.index()].name.clone(),
            TyKind::List(t) => format!("List[{}]", self.name(*t)),
            TyKind::Opt(t) => format!("{}?", self.name(*t)),
            TyKind::Obj(n, args) if args.is_empty() => n.name().to_string(),
            TyKind::Obj(n, args) => format!("{}[{}]", n.name(), list(args)),
            TyKind::Fn(params, ret) => format!("Fn({}) {}", list(params), self.name(*ret)),
            TyKind::Iface(i) => self.m.ifaces[i.index()].name.clone(),
        }
    }

    /// The description of `ty`, made on first ask. A type is registered before its parts so a
    /// cycle ends at the entry already there.
    fn ty(&mut self, ty: Ty) -> usize {
        if let Some(&i) = self.ids.get(&ty) {
            return i;
        }
        let name = self.name(ty);
        let size = self.layouts.mem(ty).size;
        // Reserve the slot first; the kinds below fill it in.
        let id = self.push(name.clone(), size, DebugKind::Pointer(None));
        self.ids.insert(ty, id);
        let kind = self.kind(ty, &name);
        self.out[id].kind = kind;
        id
    }

    fn kind(&mut self, ty: Ty, name: &str) -> DebugKind {
        let leaves = self.layouts.leaves(ty);
        let base = |e| DebugKind::Base(e);
        match self.m.types.kind(ty).clone() {
            TyKind::Unit => DebugKind::Struct(Vec::new()),
            TyKind::Bool => base(Encoding::Bool),
            TyKind::Int | TyKind::Int8 | TyKind::Int16 | TyKind::Int32 => base(Encoding::Signed),
            TyKind::UInt8 | TyKind::UInt16 | TyKind::UInt32 | TyKind::UInt64 => {
                base(Encoding::Unsigned)
            }
            TyKind::Float | TyKind::Float32 => base(Encoding::Float),
            TyKind::Ptr | TyKind::Fn(..) => DebugKind::Pointer(None),
            TyKind::Obj(n, _) if !n.is_map_or_set() => DebugKind::Pointer(None),
            TyKind::Str => self.struct_of(&leaves, &["ptr", "tagged"]),
            TyKind::Bytes => self.struct_of(&leaves, &["ptr", "len", "cap"]),
            TyKind::List(elem) => {
                let elem = self.ty(elem);
                let element_ptr = self.push(
                    format!("{}*", self.out[elem].name),
                    8,
                    DebugKind::Pointer(Some(elem)),
                );
                let len = self.leaf(Leaf::I64);
                let members = vec![
                    Member {
                        name: "ptr".into(),
                        offset: 0,
                        ty: element_ptr,
                    },
                    Member {
                        name: "len".into(),
                        offset: 8,
                        ty: len,
                    },
                    Member {
                        name: "cap".into(),
                        offset: 16,
                        ty: len,
                    },
                ];
                DebugKind::Struct(members)
            }
            TyKind::Obj(..) => {
                let names: Vec<String> = (0..leaves.len()).map(|i| format!("w{i}")).collect();
                let names: Vec<&str> = names.iter().map(String::as_str).collect();
                self.struct_of(&leaves, &names)
            }
            TyKind::Iface(_) => self.struct_of(&leaves, &["data", "vtable"]),
            TyKind::Type(r) => self.record(ty, r, name),
            TyKind::Opt(inner) => self.optional(ty, inner),
            TyKind::Alt(a) => self.alt(ty, a, name),
        }
    }

    /// Adds the field `name` of type `fty`, whose leaves sit at `offsets[idx[..]]` of the enclosing
    /// layout. The field's own type is laid out by itself, so it is shown whole only when its
    /// leaves keep their relative offsets inside the enclosing flat layout (alignment of the
    /// leaves before it can shift them); otherwise each leaf is shown as `name.k`.
    fn place(
        &mut self,
        name: &str,
        fty: Ty,
        idx: &[usize],
        offsets: &[u32],
        members: &mut Vec<Member>,
    ) {
        if idx.is_empty() {
            return;
        }
        let own = mem_layout(&self.layouts.leaves(fty));
        let first = offsets[idx[0]];
        let whole = idx.len() == own.offsets.len()
            && idx
                .iter()
                .zip(&own.offsets)
                .all(|(i, o)| i64::from(offsets[*i]) - i64::from(first) == i64::from(*o));
        if whole {
            let ty = self.ty(fty);
            members.push(Member {
                name: name.into(),
                offset: first,
                ty,
            });
            return;
        }
        for (k, (i, l)) in idx.iter().zip(self.layouts.leaves(fty)).enumerate() {
            let ty = self.leaf(l);
            members.push(Member {
                name: format!("{name}.{k}"),
                offset: offsets[*i],
                ty,
            });
        }
    }

    fn struct_of(&mut self, leaves: &[Leaf], names: &[&str]) -> DebugKind {
        let mem = mem_layout(leaves);
        DebugKind::Struct(
            leaves
                .iter()
                .zip(names)
                .zip(&mem.offsets)
                .map(|((l, n), off)| Member {
                    name: (*n).into(),
                    offset: *off,
                    ty: self.leaf(*l),
                })
                .collect(),
        )
    }

    /// A record: its fields at their memory offsets, or a pointer to them when it is indirect.
    fn record(&mut self, ty: Ty, r: TypeId, name: &str) -> DebugKind {
        let def = self.m.type_defs[r.index()].clone();
        let indirect = def.indirect;
        let (leaves, widths): (Vec<Leaf>, Vec<usize>) = if indirect {
            let widths = def
                .fields
                .iter()
                .map(|f| {
                    if self.layouts.type_field_boxed(f.1) {
                        1
                    } else {
                        self.layouts.width(f.1)
                    }
                })
                .collect();
            (self.layouts.type_block(r), widths)
        } else {
            let widths = def.fields.iter().map(|f| self.layouts.width(f.1)).collect();
            (self.layouts.leaves(ty), widths)
        };
        let mem = mem_layout(&leaves);
        let mut at = 0;
        let mut members = Vec::new();
        for (f, w) in def.fields.iter().zip(widths) {
            let idx: Vec<usize> = (at..at + w).collect();
            if indirect && self.layouts.type_field_boxed(f.1) {
                let header = self.ty(f.1);
                let ptr = self.push(
                    format!("{}*", self.out[header].name),
                    8,
                    DebugKind::Pointer(Some(header)),
                );
                members.push(Member {
                    name: f.0.clone(),
                    offset: mem.offsets[at],
                    ty: ptr,
                });
            } else {
                self.place(&f.0, f.1, &idx, &mem.offsets, &mut members);
            }
            at += w;
        }
        if !indirect {
            return DebugKind::Struct(members);
        }
        let block = self.push(
            format!("{name} block"),
            mem.size,
            DebugKind::Struct(members),
        );
        DebugKind::Pointer(Some(block))
    }

    fn optional(&mut self, ty: Ty, inner: Ty) -> DebugKind {
        if self.layouts.opt_is_nullable(inner) {
            return if self.layouts.opt_is_boxed(inner) {
                DebugKind::Pointer(Some(self.ty(inner)))
            } else {
                DebugKind::Pointer(None)
            };
        }
        let leaves = self.layouts.leaves(ty);
        if self.layouts.is_str_like(ty) {
            return self.struct_of(&leaves, &["ptr", "tagged"]);
        }
        let mem = mem_layout(&leaves);
        let present = self.leaf(Leaf::I8);
        let mut members = vec![Member {
            name: "present".into(),
            offset: 0,
            ty: present,
        }];
        let idx: Vec<usize> = (1..leaves.len()).collect();
        self.place("value", inner, &idx, &mem.offsets, &mut members);
        DebugKind::Struct(members)
    }

    /// An enum: its tag, and the payload of every case laid over the same bytes.
    fn alt(&mut self, ty: Ty, a: AltId, name: &str) -> DebugKind {
        let shape = self.layouts.shape(ty);
        let (leaves, boxed) = match &shape.alt {
            Some(AltRepr::Boxed { block, .. }) => (block.clone(), true),
            _ => (shape.leaves.clone(), false),
        };
        let mem = mem_layout(&leaves);
        let fields = self.layouts.alt_fields(a);
        let def = self.m.alts[a.index()].clone();
        let mut cases = Vec::new();
        for (c, case) in def.cases.iter().enumerate() {
            let mut members = Vec::new();
            for (f, (fty, idx)) in case.fields.iter().zip(&fields[c]) {
                if idx.is_empty() {
                    continue;
                }
                self.place(&f.0, *fty, idx, &mem.offsets, &mut members);
            }
            let case_ty = self.push(
                format!("{name}.{}", case.name),
                mem.size,
                DebugKind::Struct(members),
            );
            cases.push(Member {
                name: case.name.clone(),
                offset: 0,
                ty: case_ty,
            });
        }
        let payload = self.push(format!("{name} payload"), mem.size, DebugKind::Union(cases));
        let tag = self.leaf(Leaf::I64);
        let members = vec![
            Member {
                name: "tag".into(),
                offset: 0,
                ty: tag,
            },
            Member {
                name: "payload".into(),
                offset: 0,
                ty: payload,
            },
        ];
        if !boxed {
            return DebugKind::Struct(members);
        }
        let block = self.push(
            format!("{name} block"),
            mem.size,
            DebugKind::Struct(members),
        );
        DebugKind::Pointer(Some(block))
    }
}
