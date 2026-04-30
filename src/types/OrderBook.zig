const std = @import("std");
const Fixed = @import("root.zig").Fixed;

pub const Level = struct {
    price: Fixed,
    amount: Fixed,
};

pub const OrderBook = struct {
    symbol: []const u8,
    bids: []const Level,
    asks: []const Level,
    timestamp: ?i64,
    nonce: ?i64,
    info: ?std.json.Value,
};
