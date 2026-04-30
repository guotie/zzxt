const std = @import("std");
const Fixed = @import("root.zig").Fixed;

pub const Ticker = struct {
    symbol: []const u8,
    timestamp: ?i64,
    high: ?Fixed,
    low: ?Fixed,
    bid: ?Fixed,
    bid_volume: ?Fixed,
    ask: ?Fixed,
    ask_volume: ?Fixed,
    vwap: ?Fixed,
    open: ?Fixed,
    close: ?Fixed,
    last: ?Fixed,
    previous_close: ?Fixed,
    change: ?Fixed,
    percentage: ?Fixed,
    base_volume: ?Fixed,
    quote_volume: ?Fixed,
    info: ?std.json.Value,
};
