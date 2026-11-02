interface Secret:
    fn number() Int

interface Local:
    fn read[T: Secret](value: T) Int

export interface Visible:
    fn number() Int

export interface Exported:
    fn read[T: Visible](value: T) Int

export interface Relation[T]:
    fn compare(other: T) Int

export interface Generic[A]:
    fn read[T: Relation[T] & Relation[A]](value: T) Int
