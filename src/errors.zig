pub const Error = error{
    // Exchange errors
    AuthenticationError,
    PermissionDenied,
    BadRequest,
    BadSymbol,
    InsufficientFunds,
    InvalidOrder,
    OrderNotFound,
    NotSupported,
    // Network errors
    NetworkError,
    DDoSProtection,
    RateLimitExceeded,
    ExchangeNotAvailable,
    RequestTimeout,
    // Response errors
    BadResponse,
    NullResponse,
};
