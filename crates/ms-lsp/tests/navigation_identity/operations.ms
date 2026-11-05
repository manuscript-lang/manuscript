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
    let sample = Sample(number: 1)
    let shape = Shape.Number(sample.amount())
    let _shape = shape
    return sample.label()
