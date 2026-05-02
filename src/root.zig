const ExchangeMod = @import("Exchange.zig");
pub const Exchange = ExchangeMod.Exchange;
pub const Errors = ExchangeMod.Errors;
pub const VTable = ExchangeMod.VTable;
pub const ExchangeDescription = ExchangeMod.ExchangeDescription;
pub const OrderType = ExchangeMod.OrderType;
pub const Side = ExchangeMod.Side;
pub const types = @import("types/root.zig");
pub const errors = @import("errors.zig");
pub const json_utils = @import("json_utils.zig");
pub const signing = @import("signing.zig");
pub const rate_limiter = @import("rate_limiter.zig");
pub const http_client = @import("http_client.zig");

// Binance internal modules (for testing)
pub const binance_parsing = @import("exchanges/binance/parsing.zig");
pub const binance_types = @import("exchanges/binance/types.zig");

// Re-export types at top level for convenience
pub const Ticker = types.Ticker;
pub const OrderBook = types.OrderBook;
pub const Level = types.Level;
pub const Market = types.Market;
pub const MarketType = types.MarketType;
pub const Trade = types.Trade;
pub const TradeSide = types.TradeSide;
pub const TradeType = types.TradeType;
pub const Order = types.Order;
pub const OrderStatus = types.OrderStatus;
pub const Balance = types.Balance;
pub const Balances = types.Balances;
pub const OHLCV = types.OHLCV;
pub const Position = types.Position;
pub const PositionSide = types.PositionSide;
pub const Transaction = types.Transaction;
pub const TransactionType = types.TransactionType;
pub const TransactionStatus = types.TransactionStatus;
pub const Fee = types.Fee;
pub const Fixed = types.Fixed;
pub const FIXED_SCALE = types.FIXED_SCALE;

// Exchange implementations
pub const Binance = @import("exchanges/binance/Binance.zig");

// WebSocket
pub const WebSocket = @import("WebSocket.zig").WebSocket;
pub const BinanceWs = @import("exchanges/binance/BinanceWs.zig").BinanceWs;
