pub const Exchange = @import("Exchange.zig").Exchange;
pub const types = @import("types/root.zig");
pub const errors = @import("errors.zig");
pub const json_utils = @import("json_utils.zig");
pub const signing = @import("signing.zig");
pub const rate_limiter = @import("rate_limiter.zig");
pub const http_client = @import("http_client.zig");

// Re-export types at top level for convenience
pub const Ticker = types.Ticker;
pub const OrderBook = types.OrderBook;
pub const Level = types.Level;
pub const Market = types.Market;
pub const Trade = types.Trade;
pub const Order = types.Order;
pub const Balance = types.Balance;
pub const Balances = types.Balances;
pub const OHLCV = types.OHLCV;
pub const Position = types.Position;
pub const Transaction = types.Transaction;
pub const Fee = types.Fee;
pub const Fixed = types.Fixed;
pub const FIXED_SCALE = types.FIXED_SCALE;

// Exchange implementations
pub const Binance = @import("exchanges/binance/Binance.zig");
