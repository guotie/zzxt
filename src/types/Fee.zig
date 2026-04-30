const Fixed = @import("root.zig").Fixed;

pub const Fee = struct {
    currency: ?[]const u8,
    cost: Fixed,
    rate: ?Fixed,
};
