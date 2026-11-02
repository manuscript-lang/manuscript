type Callback:
    run: fn(Int) Int

fn read[T: Equal = Callback](value: T) T: return value

type Holder[T: Equal = Callback]:
    value: T

interface Factory:
    fn create[T: Equal = Callback](value: T) Int

impl Callback:
    fn read[T: Equal = Callback](value: T) Int: return 0
