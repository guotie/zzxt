const std = @import("std");
const Fixed = @import("root.zig").Fixed;
const Fee = @import("Fee.zig");

pub const Side = enum { buy, sell };
pub const TradeType = enum { limit, market };

pub const Trade = struct {
    id: ?[]const u8,
    symbol: []const u8,
    timestamp: ?i64,
    side: Side,
    type: ?TradeType,
    price: Fixed,
    amount: Fixed,
    cost: ?Fixed,
    fee: ?Fee,
    info: ?std.json.Value,
};
