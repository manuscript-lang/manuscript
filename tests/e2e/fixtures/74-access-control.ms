// @test: Access Control - Private members

// === Private Member Access ===

type User
  name: string
  _password: string
  
  fn authenticate(pwd: string): bool
    pwd == _password
  
  fn _hash_password(pwd: string): string
    "hashed_" + pwd

fn hack_user(u: User): string
  u._password
// @error: Cannot access private

fn call_private_method(u: User): string
  u._hash_password("secret")
// @error: Cannot access private

fn valid_access(u: User): string
  u.name

fn valid_auth(u: User): bool
  u.authenticate("test")

// === Private in Constructor ===

type Secret
  _value: string
  
  fn get(): string
    _value

fn create_secret(): Secret
  Secret("hidden")

// === Nested Types with Private ===

type Outer
  _inner: Inner
  
  fn get_inner_value(): number
    _inner.value

type Inner
  value: number
  _secret: string

fn access_nested_private(o: Outer): string
  o._inner._secret
// @error: Cannot access private

// === Private method calling private field ===

type Account
  _balance: number
  
  fn _update_balance(amount: number): void
    _balance = _balance + amount
  
  fn deposit(amount: number): void
    if amount > 0
      _update_balance(amount)
  
  fn get_balance(): number
    _balance

fn external_update(a: Account): void
  a._update_balance(100)
// @error: Cannot access private

// === Test with inheritance ===

type Base
  _secret: string
  value: number

type Derived extends Base
  extra: string

fn access_derived_private(d: Derived): string
  d._secret
// @error: Cannot access private
