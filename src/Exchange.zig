const std = @import("std");
const types = @import("types/root.zig");
const errors = @import("errors.zig");

pub const Errors = errors.Error || error{OutOfMemory};

pub const OrderType = enum { limit, market };
pub const Side = enum { buy, sell };

pub const ExchangeDescription = struct {
    name: []const u8,
    has_fetch_order_book: bool,
    has_fetch_ohlcv: bool,
    has_fetch_trades: bool,
    has_fetch_balance: bool,
    has_create_order: bool,
    has_cancel_order: bool,
    has_fetch_order: bool,
    has_fetch_open_orders: bool,
};

pub const VTable = struct {
    deinit: *const fn (ctx: *anyopaque) void,
    describe: *const fn (ctx: *anyopaque) ExchangeDescription,

    // Public API
    fetch_markets: *const fn (ctx: *anyopaque, allocator: std.mem.Allocator) Errors![]types.Market,
    fetch_ticker: *const fn (ctx: *anyopaque, allocator: std.mem.Allocator, symbol: []const u8) Errors!types.Ticker,
    fetch_tickers: *const fn (ctx: *anyopaque, allocator: std.mem.Allocator, symbols: ?[]const []const u8) Errors![]types.Ticker,
    fetch_order_book: *const fn (ctx: *anyopaque, allocator: std.mem.Allocator, symbol: []const u8, limit: ?usize) Errors!types.OrderBook,
    fetch_ohlcv: *const fn (ctx: *anyopaque, allocator: std.mem.Allocator, symbol: []const u8, timeframe: []const u8, since: ?i64, limit: ?usize) Errors![]types.OHLCV,
    fetch_trades: *const fn (ctx: *anyopaque, allocator: std.mem.Allocator, symbol: []const u8, since: ?i64, limit: ?usize) Errors![]types.Trade,

    // Private API
    fetch_balance: *const fn (ctx: *anyopaque, allocator: std.mem.Allocator) Errors!types.Balances,
    create_order: *const fn (ctx: *anyopaque, allocator: std.mem.Allocator, symbol: []const u8, order_type: OrderType, side: Side, amount: types.Fixed, price: ?types.Fixed) Errors!types.Order,
    cancel_order: *const fn (ctx: *anyopaque, allocator: std.mem.Allocator, id: []const u8, symbol: ?[]const u8) Errors!types.Order,
    fetch_order: *const fn (ctx: *anyopaque, allocator: std.mem.Allocator, id: []const u8, symbol: ?[]const u8) Errors!types.Order,
    fetch_open_orders: *const fn (ctx: *anyopaque, allocator: std.mem.Allocator, symbol: ?[]const u8) Errors![]types.Order,
};

pub const Exchange = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub fn deinit(self: Exchange) void {
        self.vtable.deinit(self.ptr);
    }

    pub fn describe(self: Exchange) ExchangeDescription {
        return self.vtable.describe(self.ptr);
    }

    pub fn fetchMarkets(self: Exchange, allocator: std.mem.Allocator) Errors![]types.Market {
        return self.vtable.fetch_markets(self.ptr, allocator);
    }

    pub fn fetchTicker(self: Exchange, allocator: std.mem.Allocator, symbol: []const u8) Errors!types.Ticker {
        return self.vtable.fetch_ticker(self.ptr, allocator, symbol);
    }

    pub fn fetchTickers(self: Exchange, allocator: std.mem.Allocator, symbols: ?[]const []const u8) Errors![]types.Ticker {
        return self.vtable.fetch_tickers(self.ptr, allocator, symbols);
    }

    pub fn fetchOrderBook(self: Exchange, allocator: std.mem.Allocator, symbol: []const u8, limit: ?usize) Errors!types.OrderBook {
        return self.vtable.fetch_order_book(self.ptr, allocator, symbol, limit);
    }

    pub fn fetchOHLCV(self: Exchange, allocator: std.mem.Allocator, symbol: []const u8, timeframe: []const u8, since: ?i64, limit: ?usize) Errors![]types.OHLCV {
        return self.vtable.fetch_ohlcv(self.ptr, allocator, symbol, timeframe, since, limit);
    }

    pub fn fetchTrades(self: Exchange, allocator: std.mem.Allocator, symbol: []const u8, since: ?i64, limit: ?usize) Errors![]types.Trade {
        return self.vtable.fetch_trades(self.ptr, allocator, symbol, since, limit);
    }

    pub fn fetchBalance(self: Exchange, allocator: std.mem.Allocator) Errors!types.Balances {
        return self.vtable.fetch_balance(self.ptr, allocator);
    }

    pub fn createOrder(self: Exchange, allocator: std.mem.Allocator, symbol: []const u8, order_type: OrderType, side: Side, amount: types.Fixed, price: ?types.Fixed) Errors!types.Order {
        return self.vtable.create_order(self.ptr, allocator, symbol, order_type, side, amount, price);
    }

    pub fn cancelOrder(self: Exchange, allocator: std.mem.Allocator, id: []const u8, symbol: ?[]const u8) Errors!types.Order {
        return self.vtable.cancel_order(self.ptr, allocator, id, symbol);
    }

    pub fn fetchOrder(self: Exchange, allocator: std.mem.Allocator, id: []const u8, symbol: ?[]const u8) Errors!types.Order {
        return self.vtable.fetch_order(self.ptr, allocator, id, symbol);
    }

    pub fn fetchOpenOrders(self: Exchange, allocator: std.mem.Allocator, symbol: ?[]const u8) Errors![]types.Order {
        return self.vtable.fetch_open_orders(self.ptr, allocator, symbol);
    }
};
