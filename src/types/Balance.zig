const std = @import("std");
const Fixed = @import("root.zig").Fixed;

pub const Balance = struct {
    free: Fixed,
    used: Fixed,
    total: Fixed,
};

pub const Balances = struct {
    entries: std.StringHashMap(Balance),
    info: ?std.json.Value,
};
