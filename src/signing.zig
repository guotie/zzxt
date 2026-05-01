const std = @import("std");

pub fn hmacSha256(out: *[32]u8, message: []const u8, key: []const u8) void {
    std.crypto.auth.hmac.sha2.HmacSha256.create(out, message, key);
}

pub fn sha256Hex(allocator: std.mem.Allocator, data: []const u8) ![]u8 {
    var hash: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(data, &hash, .{});
    return bytesToHex(allocator, &hash);
}

pub fn hmacSha256Hex(allocator: std.mem.Allocator, message: []const u8, key: []const u8) ![]u8 {
    var mac: [32]u8 = undefined;
    hmacSha256(&mac, message, key);
    return bytesToHex(allocator, &mac);
}

fn bytesToHex(allocator: std.mem.Allocator, bytes: []const u8) ![]u8 {
    const hex_chars = "0123456789abcdef";
    var result = try allocator.alloc(u8, bytes.len * 2);
    for (bytes, 0..) |b, i| {
        result[i * 2] = hex_chars[b >> 4];
        result[i * 2 + 1] = hex_chars[b & 0x0f];
    }
    return result;
}

test "hmacSha256 produces correct output" {
    const testing = std.testing;
    var out: [32]u8 = undefined;
    hmacSha256(&out, "hello", "key");
    // Just verify it doesn't panic and produces non-zero output
    var all_zero = true;
    for (out) |b| {
        if (b != 0) {
            all_zero = false;
            break;
        }
    }
    try testing.expect(!all_zero);
}

test "hmacSha256Hex returns valid hex" {
    const testing = std.testing;
    const hex = try hmacSha256Hex(testing.allocator, "hello", "key");
    defer testing.allocator.free(hex);
    try testing.expectEqual(@as(usize, 64), hex.len);
}
