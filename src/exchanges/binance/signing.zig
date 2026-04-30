const std = @import("std");
const signing = @import("../../signing.zig");

pub const Credentials = struct {
    api_key: []const u8,
    secret: []const u8,
};

pub fn signQuery(allocator: std.mem.Allocator, credentials: Credentials, query: []const u8) ![]u8 {
    const signature = try signing.hmacSha256Hex(allocator, query, credentials.secret);
    defer allocator.free(signature);

    return std.fmt.allocPrint(allocator, "{s}&signature={s}", .{ query, signature });
}

test "signQuery produces valid signature" {
    const testing = std.testing;
    const creds = Credentials{
        .api_key = "test_key",
        .secret = "test_secret",
    };
    const signed = try signQuery(testing.allocator, creds, "symbol=BTCUSDT&side=BUY&type=LIMIT");
    defer testing.allocator.free(signed);

    try testing.expect(std.mem.indexOf(u8, signed, "&signature=") != null);
}
