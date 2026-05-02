const std = @import("std");
const WebSocket = @import("../../WebSocket.zig").WebSocket;

const Allocator = std.mem.Allocator;
const Io = std.Io;

const WS_HOST = "stream.binance.com";
const WS_PORT = 9443;
const WS_BASE_PATH = "/ws";

pub const BinanceWs = struct {
    ws: WebSocket,
    allocator: Allocator,

    /// Connect to a single Binance WebSocket stream.
    /// stream examples: "btcusdt@ticker", "ethusdt@depth", "btcusdt@trade"
    pub fn init(allocator: Allocator, io: Io, stream: []const u8) !BinanceWs {
        const path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ WS_BASE_PATH, stream });
        defer allocator.free(path);

        const ws = try WebSocket.init(allocator, io, .{
            .host = WS_HOST,
            .port = WS_PORT,
            .tls = true,
            .path = path,
        });

        return .{
            .ws = ws,
            .allocator = allocator,
        };
    }

    /// Connect to the base endpoint for multi-stream subscribe/unsubscribe.
    pub fn initWithSubscribe(allocator: Allocator, io: Io) !BinanceWs {
        const ws = try WebSocket.init(allocator, io, .{
            .host = WS_HOST,
            .port = WS_PORT,
            .tls = true,
            .path = WS_BASE_PATH,
        });

        return .{
            .ws = ws,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *BinanceWs) void {
        self.ws.deinit();
    }

    /// Subscribe to streams via JSON message.
    /// streams is an array of stream names, e.g. &.{"btcusdt@ticker", "ethusdt@trade"}
    pub fn subscribe(self: *BinanceWs, streams: []const []const u8) !void {
        const json = try buildSubscribeJson(self.allocator, "SUBSCRIBE", streams, 1);
        defer self.allocator.free(json);
        try self.ws.writeText(@constCast(json));
    }

    /// Unsubscribe from streams via JSON message.
    pub fn unsubscribe(self: *BinanceWs, streams: []const []const u8) !void {
        const json = try buildSubscribeJson(self.allocator, "UNSUBSCRIBE", streams, 2);
        defer self.allocator.free(json);
        try self.ws.writeText(@constCast(json));
    }

    /// Read one WebSocket message. Returns null if no data available.
    pub fn readMessage(self: *BinanceWs) !?[]const u8 {
        return try self.ws.read();
    }

    /// Convenience: connect to btcusdt@ticker stream
    pub fn watchTicker(allocator: Allocator, io: Io, symbol: []const u8) !BinanceWs {
        const stream = try std.fmt.allocPrint(allocator, "{s}@ticker", .{symbol});
        defer allocator.free(stream);
        return init(allocator, io, stream);
    }

    /// Convenience: connect to btcusdt@depth stream
    pub fn watchOrderBook(allocator: Allocator, io: Io, symbol: []const u8) !BinanceWs {
        const stream = try std.fmt.allocPrint(allocator, "{s}@depth", .{symbol});
        defer allocator.free(stream);
        return init(allocator, io, stream);
    }

    /// Convenience: connect to btcusdt@trade stream
    pub fn watchTrades(allocator: Allocator, io: Io, symbol: []const u8) !BinanceWs {
        const stream = try std.fmt.allocPrint(allocator, "{s}@trade", .{symbol});
        defer allocator.free(stream);
        return init(allocator, io, stream);
    }

    fn buildSubscribeJson(allocator: Allocator, method: []const u8, streams: []const []const u8, id: u32) ![]u8 {
        // Calculate total length needed
        var total: usize = 20 + method.len; // {"method":"...","params":[],"id":N}
        for (streams) |s| {
            total += s.len + 3; // "s",
        }
        if (streams.len > 0) total -= 1; // remove trailing comma

        var buf = try std.ArrayList(u8).initCapacity(allocator, total);
        errdefer buf.deinit(allocator);

        try buf.appendSlice(allocator, "{\"method\":\"");
        try buf.appendSlice(allocator, method);
        try buf.appendSlice(allocator, "\",\"params\":[");
        for (streams, 0..) |s, i| {
            if (i > 0) try buf.append(allocator, ',');
            try buf.append(allocator, '"');
            try buf.appendSlice(allocator, s);
            try buf.append(allocator, '"');
        }
        try buf.appendSlice(allocator, "],\"id\":");
        // Append id as decimal
        var id_buf: [10]u8 = undefined;
        const id_str = std.fmt.bufPrint(&id_buf, "{d}", .{id}) catch unreachable;
        try buf.appendSlice(allocator, id_str);
        try buf.append(allocator, '}');

        return buf.toOwnedSlice(allocator) catch return error.OutOfMemory;
    }
};
