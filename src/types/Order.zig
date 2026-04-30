const std = @import("std");
const Fixed = @import("root.zig").Fixed;
const Fee = @import("Fee.zig");

pub const OrderStatus = enum { open, closed, canceled };
pub const OrderType = enum { limit, market };
pub const Side = enum { buy, sell };

pub const Order = struct {
    id: []const u8,
    symbol: []const u8,
    status: OrderStatus,
    type: ?OrderType,
    side: Side,
    price: ?Fixed,
    amount: Fixed,
    filled: Fixed,
    remaining: Fixed,
    cost: ?Fixed,
    average: ?Fixed,
    fee: ?Fee,
    timestamp: ?i64,
    info: ?std.json.Value,
};
