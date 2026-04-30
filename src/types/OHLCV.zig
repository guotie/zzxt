const Fixed = @import("root.zig").Fixed;

pub const OHLCV = struct {
    timestamp: i64,
    open: Fixed,
    high: Fixed,
    low: Fixed,
    close: Fixed,
    volume: Fixed,
};
