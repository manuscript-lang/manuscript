//! Types, their flattened scalar leaves, and memory layouts.
//!
//! Every value lowers to a list of scalar leaves held in SSA variables:
//! records concatenate their fields, a list is (data, length, capacity), a
//! map is one runtime handle, and alternatives are one word: a small integer
//! for a case without fields, else a pointer to a box holding the fields.

#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub enum Ty {
    Int,
    Float,
    Bool,
    Str,
    Unit,
    Record(usize),
    Alt(usize),
    List(Box<Ty>),
    Map,
    OptInt,
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub enum Leaf {
    I64,
    F64,
    I8,
}

impl Leaf {
    pub fn size(self) -> i64 {
        match self {
            Leaf::I8 => 1,
            _ => 8,
        }
    }
}

pub struct RecordDef {
    pub name: String,
    pub fields: Vec<(String, Ty)>,
}

pub struct CaseDef {
    pub name: String,
    pub fields: Vec<(String, Ty)>,
}

pub struct AltDef {
    pub name: String,
    pub cases: Vec<CaseDef>,
}

impl AltDef {
    pub fn nullary_count(&self) -> i64 {
        self.cases.iter().filter(|c| c.fields.is_empty()).count() as i64
    }

    pub fn boxed_count(&self) -> usize {
        self.cases.iter().filter(|c| !c.fields.is_empty()).count()
    }

    /// The word for a case without fields, or the tag stored in a boxed case.
    pub fn code(&self, case: usize) -> i64 {
        let nullary = self.cases[case].fields.is_empty();
        self.cases[..case].iter().filter(|c| c.fields.is_empty() == nullary).count() as i64
    }
}

/// A flattened memory layout: one (leaf, byte offset) per scalar leaf.
pub struct Layout {
    pub leaves: Vec<(Leaf, i64)>,
    pub size: i64,
    pub align: i64,
}

#[derive(Default)]
pub struct Types {
    pub records: Vec<RecordDef>,
    pub alts: Vec<AltDef>,
}

impl Types {
    pub fn name(&self, ty: &Ty) -> String {
        match ty {
            Ty::Int => "Int".into(),
            Ty::Float => "Float".into(),
            Ty::Bool => "Bool".into(),
            Ty::Str => "String".into(),
            Ty::Unit => "Unit".into(),
            Ty::Record(r) => self.records[*r].name.clone(),
            Ty::Alt(a) => self.alts[*a].name.clone(),
            Ty::List(t) => format!("List[{}]", self.name(t)),
            Ty::Map => "Map[Int, Int]".into(),
            Ty::OptInt => "Optional[Int]".into(),
        }
    }

    pub fn leaves(&self, ty: &Ty) -> Vec<Leaf> {
        match ty {
            Ty::Int | Ty::Alt(_) | Ty::Map => vec![Leaf::I64],
            Ty::Float => vec![Leaf::F64],
            Ty::Bool => vec![Leaf::I8],
            Ty::Str => vec![Leaf::I64, Leaf::I64],
            Ty::Unit => vec![],
            Ty::Record(r) => self.records[*r].fields.iter().flat_map(|(_, t)| self.leaves(t)).collect(),
            Ty::List(_) => vec![Leaf::I64, Leaf::I64, Leaf::I64],
            Ty::OptInt => vec![Leaf::I8, Leaf::I64],
        }
    }

    /// Lays out a sequence of fields the way a record or a case box stores them.
    pub fn layout_fields<'a>(&self, fields: impl Iterator<Item = &'a Ty>) -> Layout {
        let mut leaves = Vec::new();
        let mut offset = 0;
        let mut align = 1;
        for ty in fields {
            for leaf in self.leaves(ty) {
                let a = leaf.size();
                offset = (offset + a - 1) / a * a;
                align = align.max(a);
                leaves.push((leaf, offset));
                offset += a;
            }
        }
        let size = (offset + align - 1) / align * align;
        Layout { leaves, size, align }
    }

    pub fn layout(&self, ty: &Ty) -> Layout {
        self.layout_fields(std::iter::once(ty))
    }

    /// Leaf index where `field` starts within a record's leaves.
    pub fn field_leaf(&self, record: usize, field: usize) -> usize {
        self.records[record].fields[..field].iter().map(|(_, t)| self.leaves(t).len()).sum()
    }

    /// Whether a value of this type owns resources that must be released.
    pub fn needs_drop(&self, ty: &Ty) -> bool {
        match ty {
            Ty::List(_) | Ty::Map => true,
            Ty::Alt(a) => self.alts[*a].boxed_count() > 0,
            Ty::Record(r) => self.records[*r].fields.iter().any(|(_, t)| self.needs_drop(t)),
            _ => false,
        }
    }
}
