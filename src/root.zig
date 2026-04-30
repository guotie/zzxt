pub const Exchange = @import("Exchange.zig").Exchange;
pub const types = @import("types/root.zig");
pub const errors = @import("errors.zig");
pub const json_utils = @import("json_utils.zig");
pub const signing = @import("signing.zig");
pub const rate_limiter = @import("rate_limiter.zig");
pub const http_client = @import("http_client.zig");

// Re-export types at top level for convenience
pub const Ticker = types.Ticker.Ticker;
pub const OrderBook = types.OrderBook.OrderBook;
pub const Level = types.OrderBook.Level;
pub const Market = types.Market.Market;
pub const Trade = types.Trade.Trade;
pub const Order = types.Order.Order;
pub const Balance = types.Balance.Balance;
pub const Balances = types.Balance.Balances;
pub const OHLCV = types.OHLCV.OHLCV;
pub const Position = types.Position.Position;
pub const Transaction = types.Transaction.Transaction;
pub const Fee = types.Fee.Fee;
pub const Fixed = types.Fixed;
pub const FIXED_SCALE = types.FIXED_SCALE;

// Exchange implementations
pub const Binance = @import("exchanges/binance/Binance.zig");
