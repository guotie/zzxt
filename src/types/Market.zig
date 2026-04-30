const std = @import("std");
const Fixed = @import("root.zig").Fixed;

pub const MarketType = enum { spot, margin, swap, future, option };

pub const Market = struct {
    id: []const u8,
    symbol: []const u8,
    base: []const u8,
    quote: []const u8,
    active: bool,
    type: MarketType,
    spot: bool,
    swap: bool,
    future: bool,
    option: bool,
    precision: struct {
        amount: u8,
        price: u8,
    },
    limits: struct {
        amount: ?struct { min: ?Fixed, max: ?Fixed },
        price: ?struct { min: ?Fixed, max: ?Fixed },
        cost: ?struct { min: ?Fixed, max: ?Fixed },
    },
    taker: ?Fixed,
    maker: ?Fixed,
    info: ?std.json.Value,
};
