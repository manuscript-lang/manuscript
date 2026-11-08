type Failure:
    detail: String
impl Error for Failure:
    fn message() String: self.detail
