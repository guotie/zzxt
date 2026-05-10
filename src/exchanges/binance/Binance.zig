const std = @import("std");
const ExchangeMod = @import("../../Exchange.zig");
const types = @import("../../types/root.zig");
const errors = @import("../../errors.zig");
const http_client = @import("../../http_client.zig");
const rate_limiter = @import("../../rate_limiter.zig");
const signing = @import("signing.zig");
const parsing = @import("parsing.zig");
const binance_types = @import("types.zig");

const ManagedArrayList = std.array_list.Managed;

const BASE_URL = "https://api.binance.com";

pub const Config = struct {
    credentials: ?signing.Credentials = null,
    /// Optional HTTP(S) proxy URL used by REST requests.
    /// Example: "http://127.0.0.1:7890".
    proxy_url: ?[]const u8 = null,
};

pub const Binance = struct {
    http: http_client.HttpClient,
    limiter: rate_limiter.RateLimiter,
    credentials: ?signing.Credentials,
    allocator: std.mem.Allocator,
    io: std.Io,

    pub fn init(allocator: std.mem.Allocator, io: std.Io, config: Config) !ExchangeMod.Exchange {
        const self = try allocator.create(Binance);
        errdefer allocator.destroy(self);

        self.* = .{
            .http = try http_client.HttpClient.initWithConfig(allocator, io, .{
                .proxy_url = config.proxy_url,
            }),
            .limiter = rate_limiter.RateLimiter.init(1200),
            .credentials = config.credentials,
            .allocator = allocator,
            .io = io,
        };
        return .{ .ptr = self, .vtable = &vtable };
    }

    fn getTimestamp(self: *Binance) i64 {
        const ts = std.Io.Timestamp.now(self.io, .real);
        return @intCast(@divTrunc(ts.nanoseconds, 1_000_000));
    }

    fn deinitImpl(ctx: *anyopaque) void {
        const self: *Binance = @ptrCast(@alignCast(ctx));
        self.http.deinit();
        self.allocator.destroy(self);
    }

    fn describeImpl(_: *anyopaque) ExchangeMod.ExchangeDescription {
        return .{
            .name = "binance",
            .has_fetch_order_book = true,
            .has_fetch_ohlcv = true,
            .has_fetch_trades = true,
            .has_fetch_balance = true,
            .has_create_order = true,
            .has_cancel_order = true,
            .has_fetch_order = true,
            .has_fetch_open_orders = true,
        };
    }

    fn fetchMarketsImpl(ctx: *anyopaque, allocator: std.mem.Allocator) ExchangeMod.Errors![]types.Market {
        const self: *Binance = @ptrCast(@alignCast(ctx));
        self.limiter.acquire();

        const url = BASE_URL ++ "/api/v3/exchangeInfo";
        const body = self.http.get(url, null) catch return error.NetworkError;
        defer self.allocator.free(body);

        const parsed = std.json.parseFromSlice(std.json.Value, allocator, body, .{}) catch return error.BadResponse;
        defer parsed.deinit();

        return parsing.parseMarkets(parsed.value, allocator) catch return error.BadResponse;
    }

    fn fetchTickerImpl(ctx: *anyopaque, allocator: std.mem.Allocator, symbol: []const u8) ExchangeMod.Errors!types.Ticker {
        const self: *Binance = @ptrCast(@alignCast(ctx));
        self.limiter.acquire();

        const url = try std.fmt.allocPrint(self.allocator, BASE_URL ++ "/api/v3/ticker/24hr?symbol={s}", .{symbol});
        defer self.allocator.free(url);

        const body = self.http.get(url, null) catch return error.NetworkError;
        defer self.allocator.free(body);

        const parsed = std.json.parseFromSlice(binance_types.TickerResponse, allocator, body, .{ .ignore_unknown_fields = true }) catch return error.BadResponse;
        defer parsed.deinit();

        return parsing.parseTicker(symbol, parsed.value) catch return error.BadResponse;
    }

    fn fetchTickersImpl(ctx: *anyopaque, allocator: std.mem.Allocator, symbols: ?[]const []const u8) ExchangeMod.Errors![]types.Ticker {
        _ = symbols;
        const self: *Binance = @ptrCast(@alignCast(ctx));
        self.limiter.acquire();

        const url = BASE_URL ++ "/api/v3/ticker/24hr";
        const body = self.http.get(url, null) catch return error.NetworkError;
        defer self.allocator.free(body);

        const parsed = std.json.parseFromSlice([]binance_types.TickerResponse, allocator, body, .{ .ignore_unknown_fields = true }) catch return error.BadResponse;
        defer parsed.deinit();

        var tickers = try ManagedArrayList(types.Ticker).initCapacity(allocator, parsed.value.len);
        errdefer tickers.deinit();

        for (parsed.value) |t| {
            const symbol_fmt = try std.fmt.allocPrint(allocator, "{s}/{s}", .{
                t.symbol[0..3], // Simplified - real impl would parse properly
                t.symbol[3..],
            });
            try tickers.append(parsing.parseTicker(symbol_fmt, t) catch continue);
        }

        return try tickers.toOwnedSlice();
    }

    fn fetchOrderBookImpl(ctx: *anyopaque, allocator: std.mem.Allocator, symbol: []const u8, limit: ?usize) ExchangeMod.Errors!types.OrderBook {
        const self: *Binance = @ptrCast(@alignCast(ctx));
        self.limiter.acquire();

        const limit_str = if (limit) |l| try std.fmt.allocPrint(self.allocator, "&limit={d}", .{l}) else "";
        defer if (limit != null) self.allocator.free(limit_str);

        const url = try std.fmt.allocPrint(self.allocator, BASE_URL ++ "/api/v3/depth?symbol={s}{s}", .{ symbol, limit_str });
        defer self.allocator.free(url);

        const body = self.http.get(url, null) catch return error.NetworkError;
        defer self.allocator.free(body);

        const parsed = std.json.parseFromSlice(binance_types.OrderBookResponse, allocator, body, .{ .ignore_unknown_fields = true }) catch return error.BadResponse;
        defer parsed.deinit();

        var book = parsing.parseOrderBook(parsed.value, allocator) catch return error.BadResponse;
        book.symbol = symbol;
        return book;
    }

    fn fetchOHLCVImpl(ctx: *anyopaque, allocator: std.mem.Allocator, symbol: []const u8, timeframe: []const u8, since: ?i64, limit: ?usize) ExchangeMod.Errors![]types.OHLCV {
        const self: *Binance = @ptrCast(@alignCast(ctx));
        self.limiter.acquire();

        const url = if (since) |s|
            if (limit) |l|
                try std.fmt.allocPrint(self.allocator, BASE_URL ++ "/api/v3/klines?symbol={s}&interval={s}&startTime={d}&limit={d}", .{ symbol, timeframe, s, l })
            else
                try std.fmt.allocPrint(self.allocator, BASE_URL ++ "/api/v3/klines?symbol={s}&interval={s}&startTime={d}", .{ symbol, timeframe, s })
        else if (limit) |l|
            try std.fmt.allocPrint(self.allocator, BASE_URL ++ "/api/v3/klines?symbol={s}&interval={s}&limit={d}", .{ symbol, timeframe, l })
        else
            try std.fmt.allocPrint(self.allocator, BASE_URL ++ "/api/v3/klines?symbol={s}&interval={s}", .{ symbol, timeframe });
        defer self.allocator.free(url);

        const body = self.http.get(url, null) catch return error.NetworkError;
        defer self.allocator.free(body);

        const parsed = std.json.parseFromSlice([]std.json.Value, allocator, body, .{}) catch return error.BadResponse;
        defer parsed.deinit();

        var candles = try ManagedArrayList(types.OHLCV).initCapacity(allocator, parsed.value.len);
        errdefer candles.deinit();

        for (parsed.value) |kline| {
            try candles.append(parsing.parseOHLCV(kline) catch continue);
        }

        return try candles.toOwnedSlice();
    }

    fn fetchTradesImpl(ctx: *anyopaque, allocator: std.mem.Allocator, symbol: []const u8, since: ?i64, limit: ?usize) ExchangeMod.Errors![]types.Trade {
        const self: *Binance = @ptrCast(@alignCast(ctx));
        self.limiter.acquire();

        const url = if (since) |s|
            if (limit) |l|
                try std.fmt.allocPrint(self.allocator, BASE_URL ++ "/api/v3/trades?symbol={s}&startTime={d}&limit={d}", .{ symbol, s, l })
            else
                try std.fmt.allocPrint(self.allocator, BASE_URL ++ "/api/v3/trades?symbol={s}&startTime={d}", .{ symbol, s })
        else if (limit) |l|
            try std.fmt.allocPrint(self.allocator, BASE_URL ++ "/api/v3/trades?symbol={s}&limit={d}", .{ symbol, l })
        else
            try std.fmt.allocPrint(self.allocator, BASE_URL ++ "/api/v3/trades?symbol={s}", .{symbol});
        defer self.allocator.free(url);

        const body = self.http.get(url, null) catch return error.NetworkError;
        defer self.allocator.free(body);

        const parsed = std.json.parseFromSlice([]std.json.Value, allocator, body, .{}) catch return error.BadResponse;
        defer parsed.deinit();

        var trades = try ManagedArrayList(types.Trade).initCapacity(allocator, parsed.value.len);
        errdefer trades.deinit();

        for (parsed.value) |t| {
            var trade = parsing.parseTrade(t) catch continue;
            trade.symbol = symbol;
            try trades.append(trade);
        }

        return try trades.toOwnedSlice();
    }

    fn fetchBalanceImpl(ctx: *anyopaque, allocator: std.mem.Allocator) ExchangeMod.Errors!types.Balances {
        const self: *Binance = @ptrCast(@alignCast(ctx));
        const creds = self.credentials orelse return error.AuthenticationError;
        self.limiter.acquire();

        const timestamp = self.getTimestamp();
        const query = try std.fmt.allocPrint(self.allocator, "timestamp={d}", .{timestamp});
        defer self.allocator.free(query);

        const signed_query = try signing.signQuery(self.allocator, creds, query);
        defer self.allocator.free(signed_query);

        const url = try std.fmt.allocPrint(self.allocator, BASE_URL ++ "/api/v3/account?{s}", .{signed_query});
        defer self.allocator.free(url);

        const headers = [_]std.http.Header{
            .{ .name = "X-MBX-APIKEY", .value = creds.api_key },
        };

        const body = self.http.get(url, &headers) catch return error.NetworkError;
        defer self.allocator.free(body);

        const parsed = std.json.parseFromSlice(std.json.Value, allocator, body, .{}) catch return error.BadResponse;
        defer parsed.deinit();

        return parsing.parseBalance(parsed.value, allocator) catch return error.BadResponse;
    }

    fn createOrderImpl(ctx: *anyopaque, allocator: std.mem.Allocator, symbol: []const u8, order_type: ExchangeMod.OrderType, side: ExchangeMod.Side, amount: types.Fixed, price: ?types.Fixed) ExchangeMod.Errors!types.Order {
        const self: *Binance = @ptrCast(@alignCast(ctx));
        const creds = self.credentials orelse return error.AuthenticationError;
        self.limiter.acquire();

        const amount_str = try json_utils.fixedToDecimalString(self.allocator, amount);
        defer self.allocator.free(amount_str);

        var query = try std.fmt.allocPrint(self.allocator, "symbol={s}&side={s}&type={s}&quantity={s}&timestamp={d}", .{
            symbol,
            if (side == .buy) "BUY" else "SELL",
            if (order_type == .limit) "LIMIT" else "MARKET",
            amount_str,
            self.getTimestamp(),
        });
        defer self.allocator.free(query);

        if (price) |p| {
            const price_str = try json_utils.fixedToDecimalString(self.allocator, p);
            defer self.allocator.free(price_str);
            const with_price = try std.fmt.allocPrint(self.allocator, "{s}&price={s}&timeInForce=GTC", .{ query, price_str });
            self.allocator.free(query);
            query = with_price;
        }

        const signed_query = try signing.signQuery(self.allocator, creds, query);
        defer self.allocator.free(signed_query);

        const url = BASE_URL ++ "/api/v3/order";
        const headers = [_]std.http.Header{
            .{ .name = "X-MBX-APIKEY", .value = creds.api_key },
        };

        const body = self.http.post(url, signed_query, &headers) catch return error.NetworkError;
        defer self.allocator.free(body);

        const parsed = std.json.parseFromSlice(std.json.Value, allocator, body, .{}) catch return error.BadResponse;
        defer parsed.deinit();

        return parsing.parseOrder(parsed.value) catch return error.BadResponse;
    }

    fn cancelOrderImpl(ctx: *anyopaque, allocator: std.mem.Allocator, id: []const u8, symbol: ?[]const u8) ExchangeMod.Errors!types.Order {
        const self: *Binance = @ptrCast(@alignCast(ctx));
        const creds = self.credentials orelse return error.AuthenticationError;
        self.limiter.acquire();

        const sym = symbol orelse return error.BadRequest;
        const query = try std.fmt.allocPrint(self.allocator, "symbol={s}&orderId={s}&timestamp={d}", .{ sym, id, self.getTimestamp() });
        defer self.allocator.free(query);

        const signed_query = try signing.signQuery(self.allocator, creds, query);
        defer self.allocator.free(signed_query);

        const url = try std.fmt.allocPrint(self.allocator, BASE_URL ++ "/api/v3/order?{s}", .{signed_query});
        defer self.allocator.free(url);

        const headers = [_]std.http.Header{
            .{ .name = "X-MBX-APIKEY", .value = creds.api_key },
        };

        const body = self.http.delete(url, &headers) catch return error.NetworkError;
        defer self.allocator.free(body);

        const parsed = std.json.parseFromSlice(std.json.Value, allocator, body, .{}) catch return error.BadResponse;
        defer parsed.deinit();

        return parsing.parseOrder(parsed.value) catch return error.BadResponse;
    }

    fn fetchOrderImpl(ctx: *anyopaque, allocator: std.mem.Allocator, id: []const u8, symbol: ?[]const u8) ExchangeMod.Errors!types.Order {
        const self: *Binance = @ptrCast(@alignCast(ctx));
        const creds = self.credentials orelse return error.AuthenticationError;
        self.limiter.acquire();

        const sym = symbol orelse return error.BadRequest;
        const query = try std.fmt.allocPrint(self.allocator, "symbol={s}&orderId={s}&timestamp={d}", .{ sym, id, self.getTimestamp() });
        defer self.allocator.free(query);

        const signed_query = try signing.signQuery(self.allocator, creds, query);
        defer self.allocator.free(signed_query);

        const url = try std.fmt.allocPrint(self.allocator, BASE_URL ++ "/api/v3/order?{s}", .{signed_query});
        defer self.allocator.free(url);

        const headers = [_]std.http.Header{
            .{ .name = "X-MBX-APIKEY", .value = creds.api_key },
        };

        const body = self.http.get(url, &headers) catch return error.NetworkError;
        defer self.allocator.free(body);

        const parsed = std.json.parseFromSlice(std.json.Value, allocator, body, .{}) catch return error.BadResponse;
        defer parsed.deinit();

        return parsing.parseOrder(parsed.value) catch return error.BadResponse;
    }

    fn fetchOpenOrdersImpl(ctx: *anyopaque, allocator: std.mem.Allocator, symbol: ?[]const u8) ExchangeMod.Errors![]types.Order {
        const self: *Binance = @ptrCast(@alignCast(ctx));
        const creds = self.credentials orelse return error.AuthenticationError;
        self.limiter.acquire();

        var query: []const u8 = undefined;
        if (symbol) |s| {
            query = try std.fmt.allocPrint(self.allocator, "symbol={s}&timestamp={d}", .{ s, self.getTimestamp() });
        } else {
            query = try std.fmt.allocPrint(self.allocator, "timestamp={d}", .{self.getTimestamp()});
        }
        defer self.allocator.free(query);

        const signed_query = try signing.signQuery(self.allocator, creds, query);
        defer self.allocator.free(signed_query);

        const url = try std.fmt.allocPrint(self.allocator, BASE_URL ++ "/api/v3/openOrders?{s}", .{signed_query});
        defer self.allocator.free(url);

        const headers = [_]std.http.Header{
            .{ .name = "X-MBX-APIKEY", .value = creds.api_key },
        };

        const body = self.http.get(url, &headers) catch return error.NetworkError;
        defer self.allocator.free(body);

        const parsed = std.json.parseFromSlice([]std.json.Value, allocator, body, .{}) catch return error.BadResponse;
        defer parsed.deinit();

        var orders = try ManagedArrayList(types.Order).initCapacity(allocator, parsed.value.len);
        errdefer orders.deinit();

        for (parsed.value) |o| {
            try orders.append(parsing.parseOrder(o) catch continue);
        }

        return try orders.toOwnedSlice();
    }

    const vtable = ExchangeMod.VTable{
        .deinit = deinitImpl,
        .describe = describeImpl,
        .fetch_markets = fetchMarketsImpl,
        .fetch_ticker = fetchTickerImpl,
        .fetch_tickers = fetchTickersImpl,
        .fetch_order_book = fetchOrderBookImpl,
        .fetch_ohlcv = fetchOHLCVImpl,
        .fetch_trades = fetchTradesImpl,
        .fetch_balance = fetchBalanceImpl,
        .create_order = createOrderImpl,
        .cancel_order = cancelOrderImpl,
        .fetch_order = fetchOrderImpl,
        .fetch_open_orders = fetchOpenOrdersImpl,
    };
};

// Need to import json_utils for fixedToDecimalString
const json_utils = @import("../../json_utils.zig");
