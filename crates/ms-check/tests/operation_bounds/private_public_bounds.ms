interface Secret:
    fn number() Int

export interface Used:
    fn read[T: Secret](value: T) Int

export interface Unused:
    fn read[T: Secret]() Int

export interface Relation[T]:
    fn compare(other: T) Int

export interface Nested:
    fn read[T: Relation[Secret]](value: T) Int

export interface Combined:
    fn read[T: Equal & Secret](value: T) Int
