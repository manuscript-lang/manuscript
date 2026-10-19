//! MIR types: monomorphic, interned per module.

use std::collections::HashMap;

macro_rules! id_type {
    ($(#[$m:meta])* $name:ident) => {
        $(#[$m])*
        #[derive(Clone, Copy, PartialEq, Eq, Hash, PartialOrd, Ord, Debug)]
        pub struct $name(pub u32);
        impl $name {
            /// The index as a `usize`.
            pub fn index(self) -> usize {
                self.0 as usize
            }
        }
    };
}
pub(crate) use id_type;

id_type!(
    /// An interned type; see [`TyTable`].
    Ty
);
id_type!(
    /// A record declaration in [`crate::Module::records`].
    RecId
);
id_type!(
    /// An alternative (sum type) declaration in [`crate::Module::alts`].
    AltId
);
id_type!(
    /// An interface declaration in [`crate::Module::ifaces`].
    IfaceId
);

/// The shape of a type. Every type is monomorphic.
#[derive(Clone, PartialEq, Eq, Hash, Debug)]
pub enum TyKind {
    /// Zero-sized `Unit`; never stored in memory.
    Unit,
    /// `Bool`, one byte holding 0 or 1.
    Bool,
    /// `Int`, a signed 64-bit integer.
    Int,
    /// `Float`, an IEEE 754 binary64.
    Float,
    /// `String`: a reference-counted UTF-8 object.
    Str,
    /// `Bytes`: a reference-counted byte-string object.
    Bytes,
    /// A raw machine word that is not reference counted (descriptors, code
    /// addresses, erased interface data). Never retained or released.
    Ptr,
    /// A record: a reference-counted heap object with fields in declaration order.
    Rec(RecId),
    /// An alternative: a reference-counted heap object with a tag and payload.
    Alt(AltId),
    /// `List[T]`: a reference-counted heap object with inline elements.
    List(Ty),
    /// `Optional[T]`. `T` must be a scalar or a single-word reference type;
    /// pointer-like payloads use the null pointer as `none`. Lowering wraps
    /// anything else (nested optionals, interfaces) in an alternative.
    Opt(Ty),
    /// A runtime-implemented reference-counted object type such as `Map[K, V]`
    /// or `Set[T]`, named as the runtime names it.
    Obj(String, Vec<Ty>),
    /// A closure object: parameter types (all passed borrowed) and the result.
    Fn(Vec<Ty>, Ty),
    /// An interface fat pointer `{ data, vtable }`; owning it owns `data`.
    Iface(IfaceId),
}

/// Interning table for [`TyKind`]. The first seven entries are fixed.
#[derive(Clone, Debug)]
pub struct TyTable {
    kinds: Vec<TyKind>,
    index: HashMap<TyKind, Ty>,
}

impl Ty {
    /// `Unit`.
    pub const UNIT: Ty = Ty(0);
    /// `Bool`.
    pub const BOOL: Ty = Ty(1);
    /// `Int`.
    pub const INT: Ty = Ty(2);
    /// `Float`.
    pub const FLOAT: Ty = Ty(3);
    /// `String`.
    pub const STR: Ty = Ty(4);
    /// `Bytes`.
    pub const BYTES: Ty = Ty(5);
    /// Raw pointer-sized word.
    pub const PTR: Ty = Ty(6);
}

impl Default for TyTable {
    fn default() -> Self {
        Self::new()
    }
}

impl TyTable {
    /// A table holding only the builtin types.
    pub fn new() -> Self {
        let mut t = TyTable { kinds: Vec::new(), index: HashMap::new() };
        for k in [TyKind::Unit, TyKind::Bool, TyKind::Int, TyKind::Float, TyKind::Str, TyKind::Bytes, TyKind::Ptr] {
            t.intern(k);
        }
        t
    }

    /// Returns the unique [`Ty`] for `kind`.
    pub fn intern(&mut self, kind: TyKind) -> Ty {
        if let Some(t) = self.index.get(&kind) {
            return *t;
        }
        let t = Ty(self.kinds.len() as u32);
        self.kinds.push(kind.clone());
        self.index.insert(kind, t);
        t
    }

    /// The type with this shape, if it was interned.
    pub fn find(&self, kind: &TyKind) -> Option<Ty> {
        self.index.get(kind).copied()
    }

    /// The shape of `ty`.
    pub fn kind(&self, ty: Ty) -> &TyKind {
        &self.kinds[ty.index()]
    }

    /// Number of interned types.
    pub fn len(&self) -> usize {
        self.kinds.len()
    }

    /// Always false: the builtins are present.
    pub fn is_empty(&self) -> bool {
        self.kinds.is_empty()
    }

    /// `List[elem]`.
    pub fn list(&mut self, elem: Ty) -> Ty {
        self.intern(TyKind::List(elem))
    }

    /// `Optional[inner]`.
    pub fn opt(&mut self, inner: Ty) -> Ty {
        self.intern(TyKind::Opt(inner))
    }

    /// A record type.
    pub fn rec(&mut self, id: RecId) -> Ty {
        self.intern(TyKind::Rec(id))
    }

    /// An alternative type.
    pub fn alt(&mut self, id: AltId) -> Ty {
        self.intern(TyKind::Alt(id))
    }

    /// A closure type.
    pub fn func(&mut self, params: Vec<Ty>, ret: Ty) -> Ty {
        self.intern(TyKind::Fn(params, ret))
    }

    /// An interface type.
    pub fn iface(&mut self, id: IfaceId) -> Ty {
        self.intern(TyKind::Iface(id))
    }

    /// A runtime object type.
    pub fn obj(&mut self, name: &str, args: Vec<Ty>) -> Ty {
        self.intern(TyKind::Obj(name.to_string(), args))
    }

    /// Whether values of `ty` own a reference count that must be released.
    pub fn is_rc(&self, ty: Ty) -> bool {
        match self.kind(ty) {
            TyKind::Unit | TyKind::Bool | TyKind::Int | TyKind::Float | TyKind::Ptr => false,
            TyKind::Opt(inner) => self.is_rc(*inner),
            _ => true,
        }
    }

    /// Whether `ty` is `Int`, `Float` or `Bool`, which are stored inline.
    pub fn is_scalar(&self, ty: Ty) -> bool {
        matches!(self.kind(ty), TyKind::Bool | TyKind::Int | TyKind::Float)
    }

    /// Whether `ty` is a single-word heap reference (never null).
    pub fn is_ref(&self, ty: Ty) -> bool {
        matches!(
            self.kind(ty),
            TyKind::Str | TyKind::Bytes | TyKind::Rec(_) | TyKind::Alt(_) | TyKind::List(_) | TyKind::Obj(..) | TyKind::Fn(..)
        )
    }
}

/// A record declaration.
#[derive(Clone, Debug, PartialEq)]
pub struct RecordDef {
    /// Source-level name, used in the text format and diagnostics.
    pub name: String,
    /// Fields in declaration (and layout) order.
    pub fields: Vec<(String, Ty)>,
}

/// One case of an alternative.
#[derive(Clone, Debug, PartialEq)]
pub struct CaseDef {
    /// Case name.
    pub name: String,
    /// Payload fields.
    pub fields: Vec<(String, Ty)>,
}

/// An alternative (sum type) declaration. The tag of a value is the index of its case.
#[derive(Clone, Debug, PartialEq)]
pub struct AltDef {
    /// Source-level name.
    pub name: String,
    /// Cases in tag order.
    pub cases: Vec<CaseDef>,
}

/// An interface method signature. The receiver is implicit; arguments are borrowed.
#[derive(Clone, Debug, PartialEq)]
pub struct MethodSig {
    /// Method name.
    pub name: String,
    /// Parameter types after the receiver.
    pub params: Vec<Ty>,
    /// Result type.
    pub ret: Ty,
}

/// An interface declaration.
#[derive(Clone, Debug, PartialEq)]
pub struct IfaceDef {
    /// Source-level name.
    pub name: String,
    /// Methods in vtable order.
    pub methods: Vec<MethodSig>,
}
