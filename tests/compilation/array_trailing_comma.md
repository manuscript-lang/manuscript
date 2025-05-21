# Test cases for array trailing commas

## Multiline array without trailing comma (should error)

```manuscript
let a = [
  1,
  2,
  3
]; // Expect error: Multiline array literals must have a trailing comma.
```

## Multiline array with trailing comma (should pass)

```manuscript
let b = [
  1,
  2,
  3,
];
```

## Single-line array without trailing comma (should pass)

```manuscript
let c = [1, 2, 3];
```

## Single-line array with trailing comma (should pass)

```manuscript
let d = [1, 2, 3,];
```

## Empty array (should pass)

```manuscript
let e = [];
```

## Single element array with trailing comma (should pass)

```manuscript
let f = [1,];
```

## Single element array without trailing comma (should pass)

```manuscript
let g = [1];
```

## Multiline array with one element, no trailing comma (should error)
```manuscript
let h = [
  1
]; // Expect error: Multiline array literals must have a trailing comma.
```

## Multiline array with one element, with trailing comma (should pass)
```manuscript
let i = [
  1,
];
```
