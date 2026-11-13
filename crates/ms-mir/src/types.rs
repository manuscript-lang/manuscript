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
    /// A type declaration in [`crate::Module::types`].
    TypeId
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
    /// `Int8`: a signed integer in 8 bits, held in a 64-bit register until stored.
    Int8,
    /// `Int16`: a signed integer in 16 bits, held in a 64-bit register until stored.
    Int16,
    /// `Int32`: a signed integer in 32 bits, held in a 64-bit register until stored.
    Int32,
    /// `Float32`: an IEEE 754 binary32, held rounded in a binary64 register until stored.
    Float32,
    /// `UInt8`: an unsigned integer in 8 bits, held zero-extended in a 64-bit register.
    UInt8,
    /// `UInt16`: an unsigned integer in 16 bits, held zero-extended in a 64-bit register.
    UInt16,
    /// `UInt32`: an unsigned integer in 32 bits, held zero-extended in a 64-bit register.
    UInt32,
    /// `UInt64`: an unsigned integer in 64 bits; the register holds its bit pattern, so values
    /// above `i64::MAX` look negative to signed operations.
    UInt64,
    /// `String`: an owned two-word UTF-8 value.
    Str,
    /// `Bytes`: an owned byte string.
    Bytes,
    /// A raw machine word that needs no drop (descriptors, code
    /// addresses, erased interface data).
    Ptr,
    /// A type: a value with fields in declaration order.
    Type(TypeId),
    /// An alternative: a value with a tag and payload.
    Alt(AltId),
    /// `List[T]`: an owned list value.
    List(Ty),
    /// `T?`. `T` must be a scalar or a single-word reference type;
    /// pointer-like payloads use the null pointer as `none`. Lowering wraps
    /// anything else (nested optionals, interfaces) in an alternative.
    Opt(Ty),
    /// A runtime-implemented object type such as `Map[K, V]`
    /// or `Set[T]`, named as the runtime names it.
    Obj(Native, Vec<Ty>),
    /// A closure object: parameter types (all passed borrowed) and the result.
    Fn(Vec<Ty>, Ty),
    /// An interface fat pointer `{ data, vtable }`; owning it owns `data`.
    Iface(IfaceId),
}

/// Identity of a runtime-implemented object type.
#[derive(Clone, Debug, PartialEq, Eq, Hash)]
pub enum Native {
    /// `Map[K, V]`.
    Map,
    /// `Set[T]`.
    Set,
    /// `BigInt`.
    BigInt,
    /// The string-split iterator.
    SplitIter,
    /// Any other opaque runtime handle, named as the runtime names it.
    Opaque(String),
}

impl Native {
    /// The identity for a runtime name.
    pub fn from_name(name: &str) -> Native {
        match name {
            "Map" => Native::Map,
            "Set" => Native::Set,
            "BigInt" => Native::BigInt,
            "SplitIter" => Native::SplitIter,
            other => Native::Opaque(other.to_string()),
        }
    }

    /// The runtime name.
    pub fn name(&self) -> &str {
        match self {
            Native::Map => "Map",
            Native::Set => "Set",
            Native::BigInt => "BigInt",
            Native::SplitIter => "SplitIter",
            Native::Opaque(n) => n,
        }
    }

    /// Whether this is a `Map` or `Set` (inline-layout containers).
    pub fn is_map_or_set(&self) -> bool {
        matches!(self, Native::Map | Native::Set)
    }
}

/// Interning table for [`TyKind`]. The first eleven entries are fixed.
#[derive(Clone, Debug)]
pub struct TyTable {
    kinds: Vec<TyKind>,
    index: HashMap<TyKind, Ty>,
}

impl Ty {
    /// The range of a sized integer type narrower than 64 bits.
    pub fn sized_range(self) -> Option<(i64, i64)> {
        Some(match self {
            Ty::INT8 => (i8::MIN.into(), i8::MAX.into()),
            Ty::INT16 => (i16::MIN.into(), i16::MAX.into()),
            Ty::INT32 => (i32::MIN.into(), i32::MAX.into()),
            Ty::UINT8 => (0, u8::MAX.into()),
            Ty::UINT16 => (0, u16::MAX.into()),
            Ty::UINT32 => (0, u32::MAX.into()),
            _ => return None,
        })
    }
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
    /// `Int8`.
    pub const INT8: Ty = Ty(7);
    /// `Int16`.
    pub const INT16: Ty = Ty(8);
    /// `Int32`.
    pub const INT32: Ty = Ty(9);
    /// `Float32`.
    pub const FLOAT32: Ty = Ty(10);
    /// `UInt8`.
    pub const UINT8: Ty = Ty(11);
    /// `UInt16`.
    pub const UINT16: Ty = Ty(12);
    /// `UInt32`.
    pub const UINT32: Ty = Ty(13);
    /// `UInt64`.
    pub const UINT64: Ty = Ty(14);

    const SCOPE_SHIFT: u32 = 20;

    /// The descriptor key of `self` under implementation scope `scope` (`0` is none). A scope
    /// picks which module's local `Equal` and `Hashable` implementations the descriptor's
    /// glue calls; it only names a descriptor and is never the type of a value.
    pub fn scoped(self, scope: u32) -> Ty {
        Ty(self.unscoped().0 | scope << Self::SCOPE_SHIFT)
    }

    /// The type behind a descriptor key.
    pub fn unscoped(self) -> Ty {
        Ty(self.0 & ((1 << Self::SCOPE_SHIFT) - 1))
    }

    /// The implementation scope of a descriptor key.
    pub fn scope(self) -> u32 {
        self.0 >> Self::SCOPE_SHIFT
    }
}

impl Default for TyTable {
    fn default() -> Self {
        Self::new()
    }
}

impl TyTable {
    /// A table holding only the builtin types.
    pub fn new() -> Self {
        let mut t = TyTable {
            kinds: Vec::new(),
            index: HashMap::new(),
        };
        for k in [
            TyKind::Unit,
            TyKind::Bool,
            TyKind::Int,
            TyKind::Float,
            TyKind::Str,
            TyKind::Bytes,
            TyKind::Ptr,
            TyKind::Int8,
            TyKind::Int16,
            TyKind::Int32,
            TyKind::Float32,
            TyKind::UInt8,
            TyKind::UInt16,
            TyKind::UInt32,
            TyKind::UInt64,
        ] {
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

    /// `inner?`.
    pub fn opt(&mut self, inner: Ty) -> Ty {
        self.intern(TyKind::Opt(inner))
    }

    /// A type.
    pub fn named(&mut self, id: TypeId) -> Ty {
        self.intern(TyKind::Type(id))
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
        self.intern(TyKind::Obj(Native::from_name(name), args))
    }

    /// A runtime object type of a known identity.
    pub fn native(&mut self, native: Native, args: Vec<Ty>) -> Ty {
        self.intern(TyKind::Obj(native, args))
    }

    /// Whether values of `ty` own storage that must be dropped.
    pub fn is_rc(&self, ty: Ty) -> bool {
        match self.kind(ty) {
            TyKind::Unit | TyKind::Bool | TyKind::Ptr => false,
            k if Self::scalar_kind(k) => false,
            TyKind::Opt(inner) => self.is_rc(*inner),
            _ => true,
        }
    }

    fn scalar_kind(k: &TyKind) -> bool {
        matches!(
            k,
            TyKind::Int
                | TyKind::Int8
                | TyKind::Int16
                | TyKind::Int32
                | TyKind::UInt8
                | TyKind::UInt16
                | TyKind::UInt32
                | TyKind::UInt64
                | TyKind::Float
                | TyKind::Float32
        )
    }

    /// Whether `ty` is a number or `Bool`, which are stored inline.
    pub fn is_scalar(&self, ty: Ty) -> bool {
        matches!(self.kind(ty), TyKind::Bool) || Self::scalar_kind(self.kind(ty))
    }

    /// Whether `ty` is an integer of any width.
    pub fn is_int(&self, ty: Ty) -> bool {
        self.int_bits(ty).is_some()
    }

    /// Whether `ty` is a float of either width.
    pub fn is_float(&self, ty: Ty) -> bool {
        matches!(self.kind(ty), TyKind::Float | TyKind::Float32)
    }

    /// Bit width of an integer type; `Int` is 64.
    pub fn int_bits(&self, ty: Ty) -> Option<u32> {
        match self.kind(ty) {
            TyKind::Int => Some(64),
            TyKind::UInt64 => Some(64),
            TyKind::Int8 => Some(8),
            TyKind::Int16 => Some(16),
            TyKind::Int32 | TyKind::UInt32 => Some(32),
            TyKind::UInt8 => Some(8),
            TyKind::UInt16 => Some(16),
            _ => None,
        }
    }

    /// The inclusive range of values an integer type holds; `Int` has the full `i64` range.
    pub fn int_range(&self, ty: Ty) -> Option<(i128, i128)> {
        let bits = self.int_bits(ty)?;
        Some(if self.is_unsigned(ty) {
            (0, (1i128 << bits) - 1)
        } else {
            (-(1i128 << (bits - 1)), (1i128 << (bits - 1)) - 1)
        })
    }

    /// The bounds of a signed comparison on the register of an integer of type `from` that
    /// hold exactly when its value fits `to`. A `UInt64` above `i64::MAX` is a negative
    /// register, so it fits nothing narrower than itself; a value converted to `UInt64` must
    /// not be negative.
    pub fn narrow_range(&self, from: Ty, to: Ty) -> (i64, i64) {
        let (lo, hi) = self
            .int_range(to)
            .unwrap_or((i64::MIN.into(), i64::MAX.into()));
        let lo = if self.kind(from) == &TyKind::UInt64 {
            lo.max(0)
        } else {
            lo
        };
        (
            lo.max(i64::MIN.into()) as i64,
            hi.min(i64::MAX.into()) as i64,
        )
    }

    /// Whether `ty` is an unsigned integer.
    pub fn is_unsigned(&self, ty: Ty) -> bool {
        matches!(
            self.kind(ty),
            TyKind::UInt8 | TyKind::UInt16 | TyKind::UInt32 | TyKind::UInt64
        )
    }
}

/// A type declaration.
#[derive(Clone, Debug, PartialEq)]
pub struct TypeDef {
    /// Source-level name, used in the text format and diagnostics.
    pub name: String,
    /// Fields in declaration (and layout) order.
    pub fields: Vec<(String, Ty)>,
    /// Which plain-data native type this is, when the runtime implements its operations.
    /// Set where the type is lowered from its declaration; not part of the text format.
    pub native: Option<NativeType>,
    /// Whether a value is one pointer to a heap block of the fields (a layout choice for large,
    /// rarely built types such as `Error`); set where the type is lowered, not in the text format.
    pub indirect: bool,
}

/// A native type known by identity: the runtime implements its ordering and text.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum NativeType {
    /// `Timestamp` of `@std/time.ms`.
    Timestamp,
    /// `Instant` of `@std/time.ms`.
    Instant,
    /// `Decimal` of `@std/math/decimal.ms`.
    Decimal,
    /// `Duration` of `@std/time.ms`.
    Duration,
}

/// One case of an alternative.
#[derive(Clone, Debug, PartialEq)]
pub struct CaseDef {
    /// Case name.
    pub name: String,
    /// Payload fields.
    pub fields: Vec<(String, Ty)>,
}

/// Identity of a built-in standard alternative or interface that lowering special-cases.
#[derive(Copy, Clone, Debug, PartialEq, Eq, Default)]
pub enum Std {
    /// Any other declaration.
    #[default]
    None,
    /// `Result`: case 0 is `ok`, case 1 is `error`.
    Result,
    /// `Comparable`.
    Comparable,
    /// `Equal`.
    Equal,
}

impl Std {
    /// Case index of `ok` in a `Result` alternative.
    pub const OK: usize = 0;
    /// Case index of `error` in a `Result` alternative.
    pub const ERROR: usize = 1;

    /// The attribute spelling in textual MIR; `None` for [`Std::None`].
    pub fn name(self) -> Option<&'static str> {
        match self {
            Std::None => None,
            Std::Result => Some("result"),
            Std::Comparable => Some("comparable"),
            Std::Equal => Some("equal"),
        }
    }

    /// The tag a textual attribute names.
    pub fn from_name(s: &str) -> Option<Std> {
        [Std::Result, Std::Comparable, Std::Equal]
            .into_iter()
            .find(|k| k.name() == Some(s))
    }
}

impl AltDef {
    /// Index of the `ok` case when this is a `Result`.
    pub fn ok_case(&self) -> Option<usize> {
        (self.std == Std::Result).then_some(Std::OK)
    }

    /// Index of the `error` case when this is a `Result`.
    pub fn error_case(&self) -> Option<usize> {
        (self.std == Std::Result).then_some(Std::ERROR)
    }
}

/// An alternative (sum type) declaration. The tag of a value is the index of its case.
#[derive(Clone, Debug, PartialEq)]
pub struct AltDef {
    /// Source-level name.
    pub name: String,
    /// The built-in standard type this is, set when lowering declares it.
    pub std: Std,
    /// Cases in tag order.
    pub cases: Vec<CaseDef>,
    /// Bit `c` set: the payload of case `c` is borrowed from another value and never dropped by
    /// this alternative (a borrowing variant: same layout and cases as the ordinary alternative, no ownership of
    /// those cases). Zero for every ordinary alternative.
    pub borrowed: u64,
}

impl AltDef {
    /// Whether case `c` is borrowed (cases past bit 63 never are: only `Result`-shaped alternatives borrow).
    pub fn borrows(&self, c: usize) -> bool {
        u32::try_from(c)
            .ok()
            .and_then(|c| self.borrowed.checked_shr(c))
            .is_some_and(|b| b & 1 == 1)
    }
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
    /// Parameters declared as the implementing type (`Self`): the table entry receives an
    /// interface value and passes the implementation the data inside it.
    pub self_params: Vec<bool>,
}

/// An interface declaration.
#[derive(Clone, Debug, PartialEq)]
pub struct IfaceDef {
    /// Source-level name.
    pub name: String,
    /// The built-in standard type this is, set when lowering declares it.
    pub std: Std,
    /// Vtable slot of the `close` method, if the interface declares one.
    pub close: Option<u32>,
    /// Methods in vtable order.
    pub methods: Vec<MethodSig>,
}
