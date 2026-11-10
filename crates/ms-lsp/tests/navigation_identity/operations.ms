export type Sample:
    number: Int

impl Sample:
    fn amount() Int:
        return self.number

export interface Named:
    fn label() String

impl Named for Sample:
    fn label() String:
        return "sample"

export enum Shape:
    Number(value: Int)
    Empty

export fn calls() String:
    sample := Sample(number: 1)
    shape := Shape.Number(sample.amount())
    _shape := shape
    return sample.label()
