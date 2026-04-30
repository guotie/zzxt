const std = @import("std");
const Fixed = @import("root.zig").Fixed;
const Fee = @import("Fee.zig");

pub const Side = enum { long, short };

pub const Position = struct {
    symbol: []const u8,
    side: Side,
    amount: Fixed,
    entry_price: ?Fixed,
    unrealized_pnl: ?Fixed,
    leverage: ?Fixed,
    margin_type: ?enum { isolated, cross },
    timestamp: ?i64,
    info: ?std.json.Value,
};
