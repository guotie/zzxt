const std = @import("std");
const WebSocket = @import("../../WebSocket.zig").WebSocket;

const Allocator = std.mem.Allocator;
const Io = std.Io;

const WS_HOST = "stream.binance.com";
const WS_MARKET_DATA_HOST = "data-stream.binance.vision";
const WS_TESTNET_HOST = "stream.testnet.binance.vision";
const WS_PORT = 9443;
const WS_HTTPS_PORT = 443;
const WS_RAW_BASE_PATH = "/ws";
const WS_COMBINED_BASE_PATH = "/stream";

pub const BinanceWs = struct {
    ws: WebSocket,
    allocator: Allocator,
    next_id: u64,

    pub const MAX_STREAMS_PER_CONNECTION: usize = 1024;
    pub const INCOMING_MESSAGE_LIMIT_PER_SECOND: usize = 5;
    pub const SESSION_TTL_MS: u64 = 24 * 60 * 60 * 1000;

    pub const Endpoint = enum {
        production,
        market_data,
        testnet,

        pub fn host(self: Endpoint) []const u8 {
            return switch (self) {
                .production => WS_HOST,
                .market_data => WS_MARKET_DATA_HOST,
                .testnet => WS_TESTNET_HOST,
            };
        }

        pub fn defaultPort(self: Endpoint) u16 {
            return switch (self) {
                .production => WS_PORT,
                .market_data, .testnet => WS_HTTPS_PORT,
            };
        }
    };

    pub const TimeUnit = enum {
        millisecond,
        microsecond,

        pub fn queryValue(self: TimeUnit) ?[]const u8 {
            return switch (self) {
                .millisecond => null,
                .microsecond => "MICROSECOND",
            };
        }
    };

    pub const Options = struct {
        endpoint: Endpoint = .production,
        port: ?u16 = null,
        time_unit: TimeUnit = .millisecond,
        max_size: usize = 65536,

        pub fn resolvedPort(self: Options) u16 {
            return self.port orelse self.endpoint.defaultPort();
        }
    };

    pub const RequestId = union(enum) {
        int: u64,
        string: []const u8,
        null,

        pub fn validate(self: RequestId) !void {
            switch (self) {
                .int, .null => {},
                .string => |value| {
                    if (value.len == 0 or value.len > 36) return error.InvalidRequestId;
                    for (value) |c| {
                        if (!std.ascii.isAlphanumeric(c)) return error.InvalidRequestId;
                    }
                },
            }
        }

        pub fn jsonStringify(self: RequestId, writer: anytype) !void {
            switch (self) {
                .int => |value| try writer.write(value),
                .string => |value| try writer.write(value),
                .null => try writer.write(@as(?u8, null)),
            }
        }
    };

    pub const ControlMethod = enum {
        subscribe,
        unsubscribe,
        list_subscriptions,
        set_property,
        get_property,

        pub fn binanceName(self: ControlMethod) []const u8 {
            return switch (self) {
                .subscribe => "SUBSCRIBE",
                .unsubscribe => "UNSUBSCRIBE",
                .list_subscriptions => "LIST_SUBSCRIPTIONS",
                .set_property => "SET_PROPERTY",
                .get_property => "GET_PROPERTY",
            };
        }
    };

    pub const DepthSpeed = enum {
        one_second,
        hundred_ms,

        pub fn suffix(self: DepthSpeed) []const u8 {
            return switch (self) {
                .one_second => "",
                .hundred_ms => "@100ms",
            };
        }
    };

    pub const DepthLevels = enum {
        five,
        ten,
        twenty,

        pub fn value(self: DepthLevels) u8 {
            return switch (self) {
                .five => 5,
                .ten => 10,
                .twenty => 20,
            };
        }
    };

    pub const RollingWindow = enum {
        one_hour,
        four_hour,
        one_day,

        pub fn value(self: RollingWindow) []const u8 {
            return switch (self) {
                .one_hour => "1h",
                .four_hour => "4h",
                .one_day => "1d",
            };
        }
    };

    pub const CombinedMessage = struct {
        stream: []const u8,
        data: std.json.Value,
    };

    pub const ControlResponse = struct {
        result: std.json.Value = .null,
        id: std.json.Value = .null,
        code: ?i64 = null,
        msg: ?[]const u8 = null,
    };

    /// Connect to a single raw Binance WebSocket stream.
    /// Stream examples: "btcusdt@ticker", "ethusdt@depth@100ms", "!ticker@arr".
    pub fn init(allocator: Allocator, io: Io, stream: []const u8) !BinanceWs {
        return initRawWithOptions(allocator, io, stream, .{});
    }

    pub fn initRawWithOptions(allocator: Allocator, io: Io, stream: []const u8, options: Options) !BinanceWs {
        const path = try buildRawPath(allocator, stream, options.time_unit);
        defer allocator.free(path);
        return connectWithPath(allocator, io, path, options);
    }

    /// Connect to a combined stream URL, e.g. /stream?streams=btcusdt@trade/ethusdt@ticker.
    pub fn initCombined(allocator: Allocator, io: Io, streams: []const []const u8) !BinanceWs {
        return initCombinedWithOptions(allocator, io, streams, .{});
    }

    pub fn initCombinedWithOptions(allocator: Allocator, io: Io, streams: []const []const u8, options: Options) !BinanceWs {
        const path = try buildCombinedPath(allocator, streams, options.time_unit);
        defer allocator.free(path);
        return connectWithPath(allocator, io, path, options);
    }

    /// Connect to the base endpoint for runtime SUBSCRIBE/UNSUBSCRIBE control messages.
    pub fn initWithSubscribe(allocator: Allocator, io: Io) !BinanceWs {
        return initBaseWithOptions(allocator, io, .{});
    }

    pub fn initBase(allocator: Allocator, io: Io) !BinanceWs {
        return initBaseWithOptions(allocator, io, .{});
    }

    pub fn initBaseWithOptions(allocator: Allocator, io: Io, options: Options) !BinanceWs {
        const path = try buildBasePath(allocator, options.time_unit);
        defer allocator.free(path);
        return connectWithPath(allocator, io, path, options);
    }

    pub fn deinit(self: *BinanceWs) void {
        self.ws.deinit();
    }

    /// Subscribe to streams via Binance's runtime control protocol.
    pub fn subscribe(self: *BinanceWs, streams: []const []const u8) !void {
        try self.subscribeWithId(streams, self.nextRequestId());
    }

    pub fn subscribeWithId(self: *BinanceWs, streams: []const []const u8, id: RequestId) !void {
        const json = try buildStreamControlJson(self.allocator, .subscribe, streams, id);
        try self.writeOwnedJson(json);
    }

    pub fn unsubscribe(self: *BinanceWs, streams: []const []const u8) !void {
        try self.unsubscribeWithId(streams, self.nextRequestId());
    }

    pub fn unsubscribeWithId(self: *BinanceWs, streams: []const []const u8, id: RequestId) !void {
        const json = try buildStreamControlJson(self.allocator, .unsubscribe, streams, id);
        try self.writeOwnedJson(json);
    }

    pub fn listSubscriptions(self: *BinanceWs) !void {
        try self.listSubscriptionsWithId(self.nextRequestId());
    }

    pub fn listSubscriptionsWithId(self: *BinanceWs, id: RequestId) !void {
        const json = try buildNoParamControlJson(self.allocator, .list_subscriptions, id);
        try self.writeOwnedJson(json);
    }

    pub fn setCombined(self: *BinanceWs, enabled: bool) !void {
        try self.setCombinedWithId(enabled, self.nextRequestId());
    }

    pub fn setCombinedWithId(self: *BinanceWs, enabled: bool, id: RequestId) !void {
        const json = try buildCombinedPropertyJson(self.allocator, .set_property, enabled, id);
        try self.writeOwnedJson(json);
    }

    pub fn getCombined(self: *BinanceWs) !void {
        try self.getCombinedWithId(self.nextRequestId());
    }

    pub fn getCombinedWithId(self: *BinanceWs, id: RequestId) !void {
        const json = try buildCombinedPropertyJson(self.allocator, .get_property, null, id);
        try self.writeOwnedJson(json);
    }

    /// Send a pre-built control JSON payload.
    pub fn sendRawText(self: *BinanceWs, data: []const u8) !void {
        const json = try self.allocator.dupe(u8, data);
        try self.writeOwnedJson(json);
    }

    /// Read one WebSocket message. Returns null if no data is currently available.
    pub fn readMessage(self: *BinanceWs) !?[]const u8 {
        return try self.ws.read();
    }

    pub fn readJson(self: *BinanceWs, allocator: Allocator) !?std.json.Parsed(std.json.Value) {
        const msg = try self.readMessage() orelse return null;
        return try std.json.parseFromSlice(std.json.Value, allocator, msg, .{});
    }

    pub fn readCombinedMessage(self: *BinanceWs, allocator: Allocator) !?std.json.Parsed(CombinedMessage) {
        const msg = try self.readMessage() orelse return null;
        return try std.json.parseFromSlice(CombinedMessage, allocator, msg, .{ .ignore_unknown_fields = true });
    }

    pub fn readControlResponse(self: *BinanceWs, allocator: Allocator) !?std.json.Parsed(ControlResponse) {
        const msg = try self.readMessage() orelse return null;
        return try std.json.parseFromSlice(ControlResponse, allocator, msg, .{ .ignore_unknown_fields = true });
    }

    /// Convenience: connect to <symbol>@ticker.
    pub fn watchTicker(allocator: Allocator, io: Io, symbol: []const u8) !BinanceWs {
        return watchTickerWithOptions(allocator, io, symbol, .{});
    }

    pub fn watchTickerWithOptions(allocator: Allocator, io: Io, symbol: []const u8, options: Options) !BinanceWs {
        const stream = try streamTicker(allocator, symbol);
        defer allocator.free(stream);
        return initRawWithOptions(allocator, io, stream, options);
    }

    /// Convenience: connect to <symbol>@depth.
    pub fn watchOrderBook(allocator: Allocator, io: Io, symbol: []const u8) !BinanceWs {
        return watchDiffOrderBookWithOptions(allocator, io, symbol, .one_second, .{});
    }

    pub fn watchOrderBookFast(allocator: Allocator, io: Io, symbol: []const u8) !BinanceWs {
        return watchDiffOrderBookWithOptions(allocator, io, symbol, .hundred_ms, .{});
    }

    pub fn watchDiffOrderBookWithOptions(allocator: Allocator, io: Io, symbol: []const u8, speed: DepthSpeed, options: Options) !BinanceWs {
        const stream = try streamDiffDepth(allocator, symbol, speed);
        defer allocator.free(stream);
        return initRawWithOptions(allocator, io, stream, options);
    }

    pub fn watchPartialOrderBook(allocator: Allocator, io: Io, symbol: []const u8, levels: DepthLevels, speed: DepthSpeed) !BinanceWs {
        const stream = try streamPartialDepth(allocator, symbol, levels, speed);
        defer allocator.free(stream);
        return init(allocator, io, stream);
    }

    /// Convenience: connect to <symbol>@trade.
    pub fn watchTrades(allocator: Allocator, io: Io, symbol: []const u8) !BinanceWs {
        const stream = try streamTrade(allocator, symbol);
        defer allocator.free(stream);
        return init(allocator, io, stream);
    }

    pub fn watchAggregateTrades(allocator: Allocator, io: Io, symbol: []const u8) !BinanceWs {
        const stream = try streamAggTrade(allocator, symbol);
        defer allocator.free(stream);
        return init(allocator, io, stream);
    }

    pub fn watchKline(allocator: Allocator, io: Io, symbol: []const u8, interval: []const u8) !BinanceWs {
        const stream = try streamKline(allocator, symbol, interval);
        defer allocator.free(stream);
        return init(allocator, io, stream);
    }

    pub fn watchMiniTicker(allocator: Allocator, io: Io, symbol: []const u8) !BinanceWs {
        const stream = try streamMiniTicker(allocator, symbol);
        defer allocator.free(stream);
        return init(allocator, io, stream);
    }

    pub fn watchBookTicker(allocator: Allocator, io: Io, symbol: []const u8) !BinanceWs {
        const stream = try streamBookTicker(allocator, symbol);
        defer allocator.free(stream);
        return init(allocator, io, stream);
    }

    pub fn watchAveragePrice(allocator: Allocator, io: Io, symbol: []const u8) !BinanceWs {
        const stream = try streamAveragePrice(allocator, symbol);
        defer allocator.free(stream);
        return init(allocator, io, stream);
    }

    pub fn watchCombined(allocator: Allocator, io: Io, streams: []const []const u8) !BinanceWs {
        return initCombined(allocator, io, streams);
    }

    pub fn buildBasePath(allocator: Allocator, time_unit: TimeUnit) ![]u8 {
        if (time_unit.queryValue()) |value| {
            return try std.fmt.allocPrint(allocator, "{s}?timeUnit={s}", .{ WS_RAW_BASE_PATH, value });
        }
        return try allocator.dupe(u8, WS_RAW_BASE_PATH);
    }

    pub fn buildRawPath(allocator: Allocator, stream: []const u8, time_unit: TimeUnit) ![]u8 {
        validateStreamName(stream) catch |err| return err;
        if (time_unit.queryValue()) |value| {
            return try std.fmt.allocPrint(allocator, "{s}/{s}?timeUnit={s}", .{ WS_RAW_BASE_PATH, stream, value });
        }
        return try std.fmt.allocPrint(allocator, "{s}/{s}", .{ WS_RAW_BASE_PATH, stream });
    }

    pub fn buildCombinedPath(allocator: Allocator, streams: []const []const u8, time_unit: TimeUnit) ![]u8 {
        try validateStreamList(streams);

        var joined = std.ArrayList(u8).empty;
        defer joined.deinit(allocator);

        for (streams, 0..) |stream, i| {
            if (i > 0) try joined.append(allocator, '/');
            try joined.appendSlice(allocator, stream);
        }

        const joined_slice = try joined.toOwnedSlice(allocator);
        defer allocator.free(joined_slice);

        if (time_unit.queryValue()) |value| {
            return try std.fmt.allocPrint(allocator, "{s}?streams={s}&timeUnit={s}", .{ WS_COMBINED_BASE_PATH, joined_slice, value });
        }
        return try std.fmt.allocPrint(allocator, "{s}?streams={s}", .{ WS_COMBINED_BASE_PATH, joined_slice });
    }

    pub fn buildStreamControlJson(allocator: Allocator, method: ControlMethod, streams: []const []const u8, id: RequestId) ![]u8 {
        try validateStreamList(streams);
        try id.validate();

        const Payload = struct {
            method: []const u8,
            params: []const []const u8,
            id: RequestId,
        };

        return try std.json.Stringify.valueAlloc(allocator, Payload{
            .method = method.binanceName(),
            .params = streams,
            .id = id,
        }, .{});
    }

    pub fn buildNoParamControlJson(allocator: Allocator, method: ControlMethod, id: RequestId) ![]u8 {
        try id.validate();

        const Payload = struct {
            method: []const u8,
            id: RequestId,
        };

        return try std.json.Stringify.valueAlloc(allocator, Payload{
            .method = method.binanceName(),
            .id = id,
        }, .{});
    }

    pub fn buildCombinedPropertyJson(allocator: Allocator, method: ControlMethod, enabled: ?bool, id: RequestId) ![]u8 {
        try id.validate();
        if (method != .set_property and method != .get_property) return error.InvalidControlMethod;
        if (method == .set_property and enabled == null) return error.MissingPropertyValue;
        if (method == .get_property and enabled != null) return error.UnexpectedPropertyValue;

        const CombinedParams = struct {
            enabled: ?bool,

            pub fn jsonStringify(self: @This(), writer: anytype) !void {
                try writer.beginArray();
                try writer.write("combined");
                if (self.enabled) |value| {
                    try writer.write(value);
                }
                try writer.endArray();
            }
        };

        const Payload = struct {
            method: []const u8,
            params: CombinedParams,
            id: RequestId,
        };

        return try std.json.Stringify.valueAlloc(allocator, Payload{
            .method = method.binanceName(),
            .params = .{ .enabled = enabled },
            .id = id,
        }, .{});
    }

    pub fn streamReferencePrice(allocator: Allocator, symbol: []const u8) ![]u8 {
        return symbolStream(allocator, symbol, "referencePrice");
    }

    pub fn streamAggTrade(allocator: Allocator, symbol: []const u8) ![]u8 {
        return symbolStream(allocator, symbol, "aggTrade");
    }

    pub fn streamTrade(allocator: Allocator, symbol: []const u8) ![]u8 {
        return symbolStream(allocator, symbol, "trade");
    }

    pub fn streamKline(allocator: Allocator, symbol: []const u8, interval: []const u8) ![]u8 {
        return streamKlineWithTimezone(allocator, symbol, interval, null);
    }

    pub fn streamKlineUtc8(allocator: Allocator, symbol: []const u8, interval: []const u8) ![]u8 {
        return streamKlineWithTimezone(allocator, symbol, interval, "+08:00");
    }

    pub fn streamKlineWithTimezone(allocator: Allocator, symbol: []const u8, interval: []const u8, timezone_offset: ?[]const u8) ![]u8 {
        validateStreamName(interval) catch return error.InvalidInterval;

        const lower = try allocLowercase(allocator, symbol);
        defer allocator.free(lower);

        if (timezone_offset) |offset| {
            try validateTimezoneOffset(offset);
            return try std.fmt.allocPrint(allocator, "{s}@kline_{s}@{s}", .{ lower, interval, offset });
        }

        return try std.fmt.allocPrint(allocator, "{s}@kline_{s}", .{ lower, interval });
    }

    pub fn streamMiniTicker(allocator: Allocator, symbol: []const u8) ![]u8 {
        return symbolStream(allocator, symbol, "miniTicker");
    }

    pub fn streamTicker(allocator: Allocator, symbol: []const u8) ![]u8 {
        return symbolStream(allocator, symbol, "ticker");
    }

    pub fn streamRollingWindowTicker(allocator: Allocator, symbol: []const u8, window: RollingWindow) ![]u8 {
        const lower = try allocLowercase(allocator, symbol);
        defer allocator.free(lower);
        return try std.fmt.allocPrint(allocator, "{s}@ticker_{s}", .{ lower, window.value() });
    }

    pub fn streamAllRollingWindowTickers(window: RollingWindow) []const u8 {
        return switch (window) {
            .one_hour => "!ticker_1h@arr",
            .four_hour => "!ticker_4h@arr",
            .one_day => "!ticker_1d@arr",
        };
    }

    pub fn streamBookTicker(allocator: Allocator, symbol: []const u8) ![]u8 {
        return symbolStream(allocator, symbol, "bookTicker");
    }

    pub fn streamAveragePrice(allocator: Allocator, symbol: []const u8) ![]u8 {
        return symbolStream(allocator, symbol, "avgPrice");
    }

    pub fn streamPartialDepth(allocator: Allocator, symbol: []const u8, levels: DepthLevels, speed: DepthSpeed) ![]u8 {
        const lower = try allocLowercase(allocator, symbol);
        defer allocator.free(lower);
        return try std.fmt.allocPrint(allocator, "{s}@depth{d}{s}", .{ lower, levels.value(), speed.suffix() });
    }

    pub fn streamDiffDepth(allocator: Allocator, symbol: []const u8, speed: DepthSpeed) ![]u8 {
        const lower = try allocLowercase(allocator, symbol);
        defer allocator.free(lower);
        return try std.fmt.allocPrint(allocator, "{s}@depth{s}", .{ lower, speed.suffix() });
    }

    pub fn streamAllMiniTickers() []const u8 {
        return "!miniTicker@arr";
    }

    pub fn streamAllTickers() []const u8 {
        return "!ticker@arr";
    }

    pub fn streamAllBookTickers() []const u8 {
        return "!bookTicker";
    }

    fn connectWithPath(allocator: Allocator, io: Io, path: []const u8, options: Options) !BinanceWs {
        const ws = try WebSocket.init(allocator, io, .{
            .host = options.endpoint.host(),
            .port = options.resolvedPort(),
            .tls = true,
            .path = path,
            .max_size = options.max_size,
        });

        return .{
            .ws = ws,
            .allocator = allocator,
            .next_id = 1,
        };
    }

    fn nextRequestId(self: *BinanceWs) RequestId {
        const id = self.next_id;
        self.next_id +|= 1;
        return .{ .int = id };
    }

    fn writeOwnedJson(self: *BinanceWs, json: []u8) !void {
        defer self.allocator.free(json);
        try self.ws.writeText(json);
    }

    fn symbolStream(allocator: Allocator, symbol: []const u8, suffix: []const u8) ![]u8 {
        const lower = try allocLowercase(allocator, symbol);
        defer allocator.free(lower);
        return try std.fmt.allocPrint(allocator, "{s}@{s}", .{ lower, suffix });
    }

    fn allocLowercase(allocator: Allocator, value: []const u8) ![]u8 {
        validateStreamName(value) catch return error.InvalidSymbol;
        const lower = try allocator.dupe(u8, value);
        for (lower) |*c| {
            c.* = std.ascii.toLower(c.*);
        }
        return lower;
    }

    fn validateStreamList(streams: []const []const u8) !void {
        if (streams.len == 0) return error.EmptyStreamList;
        if (streams.len > MAX_STREAMS_PER_CONNECTION) return error.TooManyStreams;
        for (streams) |stream| {
            try validateStreamName(stream);
        }
    }

    fn validateStreamName(stream: []const u8) !void {
        if (stream.len == 0) return error.EmptyStreamName;
    }

    fn validateTimezoneOffset(offset: []const u8) !void {
        if (offset.len != 6) return error.InvalidTimezoneOffset;
        if (offset[0] != '+' and offset[0] != '-') return error.InvalidTimezoneOffset;
        if (!std.ascii.isDigit(offset[1]) or !std.ascii.isDigit(offset[2])) return error.InvalidTimezoneOffset;
        if (offset[3] != ':') return error.InvalidTimezoneOffset;
        if (!std.ascii.isDigit(offset[4]) or !std.ascii.isDigit(offset[5])) return error.InvalidTimezoneOffset;
    }
};

test "BinanceWs: build raw and combined paths" {
    const allocator = std.testing.allocator;

    const raw = try BinanceWs.buildRawPath(allocator, "btcusdt@trade", .microsecond);
    defer allocator.free(raw);
    try std.testing.expectEqualStrings("/ws/btcusdt@trade?timeUnit=MICROSECOND", raw);

    const combined = try BinanceWs.buildCombinedPath(allocator, &.{ "btcusdt@trade", "ethusdt@depth@100ms" }, .millisecond);
    defer allocator.free(combined);
    try std.testing.expectEqualStrings("/stream?streams=btcusdt@trade/ethusdt@depth@100ms", combined);
}

test "BinanceWs: stream helper names" {
    const allocator = std.testing.allocator;

    const trade = try BinanceWs.streamTrade(allocator, "BTCUSDT");
    defer allocator.free(trade);
    try std.testing.expectEqualStrings("btcusdt@trade", trade);

    const agg_trade = try BinanceWs.streamAggTrade(allocator, "ETHUSDT");
    defer allocator.free(agg_trade);
    try std.testing.expectEqualStrings("ethusdt@aggTrade", agg_trade);

    const kline_utc8 = try BinanceWs.streamKlineUtc8(allocator, "BTCUSDT", "1m");
    defer allocator.free(kline_utc8);
    try std.testing.expectEqualStrings("btcusdt@kline_1m@+08:00", kline_utc8);

    const partial_depth = try BinanceWs.streamPartialDepth(allocator, "BNBUSDT", .twenty, .hundred_ms);
    defer allocator.free(partial_depth);
    try std.testing.expectEqualStrings("bnbusdt@depth20@100ms", partial_depth);

    try std.testing.expectEqualStrings("!ticker_4h@arr", BinanceWs.streamAllRollingWindowTickers(.four_hour));
}

test "BinanceWs: control JSON builders" {
    const allocator = std.testing.allocator;

    const sub = try BinanceWs.buildStreamControlJson(allocator, .subscribe, &.{ "btcusdt@aggTrade", "btcusdt@depth" }, .{ .int = 1 });
    defer allocator.free(sub);
    try std.testing.expectEqualStrings("{\"method\":\"SUBSCRIBE\",\"params\":[\"btcusdt@aggTrade\",\"btcusdt@depth\"],\"id\":1}", sub);

    const list = try BinanceWs.buildNoParamControlJson(allocator, .list_subscriptions, .{ .int = 3 });
    defer allocator.free(list);
    try std.testing.expectEqualStrings("{\"method\":\"LIST_SUBSCRIPTIONS\",\"id\":3}", list);

    const set = try BinanceWs.buildCombinedPropertyJson(allocator, .set_property, true, .{ .string = "abc123" });
    defer allocator.free(set);
    try std.testing.expectEqualStrings("{\"method\":\"SET_PROPERTY\",\"params\":[\"combined\",true],\"id\":\"abc123\"}", set);

    const get = try BinanceWs.buildCombinedPropertyJson(allocator, .get_property, null, .null);
    defer allocator.free(get);
    try std.testing.expectEqualStrings("{\"method\":\"GET_PROPERTY\",\"params\":[\"combined\"],\"id\":null}", get);
}

test "BinanceWs: parse combined message envelope" {
    const allocator = std.testing.allocator;

    const parsed = try std.json.parseFromSlice(BinanceWs.CombinedMessage, allocator, "{\"stream\":\"btcusdt@trade\",\"data\":{\"e\":\"trade\",\"s\":\"BTCUSDT\"}}", .{});
    defer parsed.deinit();

    try std.testing.expectEqualStrings("btcusdt@trade", parsed.value.stream);
    try std.testing.expectEqualStrings("trade", parsed.value.data.object.get("e").?.string);
}
