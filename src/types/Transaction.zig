const std = @import("std");
const Fixed = @import("root.zig").Fixed;

pub const TransactionType = enum { deposit, withdrawal };
pub const TransactionStatus = enum { pending, ok, failed, canceled };

pub const Transaction = struct {
    id: []const u8,
    type: TransactionType,
    currency: []const u8,
    amount: Fixed,
    fee: ?Fixed,
    address: ?[]const u8,
    tag: ?[]const u8,
    network: ?[]const u8,
    status: TransactionStatus,
    timestamp: ?i64,
    info: ?std.json.Value,
};
