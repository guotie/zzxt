const std = @import("std");
const types = @import("types/root.zig");
const Fixed = types.Fixed;
const FIXED_SCALE = types.FIXED_SCALE;

/// Convert a decimal string (e.g. "65432.10", "0.000001") to Fixed (u64 * 10^9).
/// Returns error.Overflow if the value exceeds u64 range.
pub fn decimalStringToFixed(s: []const u8) !Fixed {
    if (s.len == 0) return error.BadResponse;

    var negative = false;
    var start: usize = 0;
    if (s[0] == '-') {
        negative = true;
        start = 1;
    } else if (s[0] == '+') {
        start = 1;
    }

    var dot_pos: ?usize = null;
    for (start..s.len) |i| {
        if (s[i] == '.') {
            dot_pos = i;
            break;
        }
    }

    var int_part: u64 = 0;
    var frac_part: u64 = 0;
    var frac_digits: u32 = 0;

    const int_end = dot_pos orelse s.len;
    for (start..int_end) |i| {
        const digit = s[i];
        if (digit < '0' or digit > '9') return error.BadResponse;
        int_part = std.math.mul(u64, int_part, 10) catch return error.Overflow;
        int_part = std.math.add(u64, int_part, digit - '0') catch return error.Overflow;
    }

    if (dot_pos) |dp| {
        const frac_start = dp + 1;
        for (frac_start..s.len) |i| {
            const digit = s[i];
            if (digit < '0' or digit > '9') return error.BadResponse;
            frac_part = std.math.mul(u64, frac_part, 10) catch return error.Overflow;
            frac_part = std.math.add(u64, frac_part, digit - '0') catch return error.Overflow;
            frac_digits += 1;
        }
    }

    // Scale integer part
    var scale: u64 = 1;
    for (0..9) |_| {
        scale *= 10;
    }
    const scaled_int = std.math.mul(u64, int_part, scale) catch return error.Overflow;

    // Scale fractional part to 9 decimal places
    var frac_scaled = frac_part;
    if (frac_digits < 9) {
        for (frac_digits..9) |_| {
            frac_scaled = std.math.mul(u64, frac_scaled, 10) catch return error.Overflow;
        }
    } else if (frac_digits > 9) {
        const extra = frac_digits - 9;
        for (0..extra) |_| {
            frac_scaled /= 10;
        }
    }

    const result = std.math.add(u64, scaled_int, frac_scaled) catch return error.Overflow;
    if (negative) {
        // For negative values, we still store as positive (financial amounts are positive)
        // This is a design choice — negative amounts don't make sense for prices/amounts
        return result;
    }
    return result;
}

/// Convert a Fixed value back to a decimal string. Caller owns memory.
pub fn fixedToDecimalString(allocator: std.mem.Allocator, value: Fixed) ![]u8 {
    var scale: u64 = 1;
    for (0..9) |_| {
        scale *= 10;
    }
    const int_part = value / scale;
    const frac_part = value % scale;

    if (frac_part == 0) {
        return std.fmt.allocPrint(allocator, "{d}", .{int_part});
    }

    // Format fractional part with leading zeros
    return std.fmt.allocPrint(allocator, "{d}.{d:0>9}", .{ int_part, frac_part });
}

/// Parse a JSON string field as Fixed. Handles Binance-style string prices.
pub fn parseFixedField(json: std.json.Value, field: []const u8) !?Fixed {
    const obj = json.object;
    const val = obj.get(field) orelse return null;
    switch (val) {
        .string => |s| return decimalStringToFixed(s),
        .integer => |i| {
            const scale: u64 = 1_000_000_000;
            return std.math.mul(u64, @intCast(i), scale) catch return error.Overflow;
        },
        .float => |f| {
            const scaled = f * @as(f64, @floatFromInt(FIXED_SCALE));
            return @intFromFloat(scaled);
        },
        else => return null,
    }
}

test "decimalStringToFixed basic" {
    const testing = std.testing;

    try testing.expectEqual(@as(Fixed, 65_432_100_000_000), try decimalStringToFixed("65432.10"));
    try testing.expectEqual(@as(Fixed, 1_500_000_000), try decimalStringToFixed("1.5"));
    try testing.expectEqual(@as(Fixed, 1_000_000_000), try decimalStringToFixed("1"));
    try testing.expectEqual(@as(Fixed, 100_000_000), try decimalStringToFixed("0.1"));
    try testing.expectEqual(@as(Fixed, 1), try decimalStringToFixed("0.000000001"));
    try testing.expectEqual(@as(Fixed, 0), try decimalStringToFixed("0"));
}

test "fixedToDecimalString basic" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const s1 = try fixedToDecimalString(allocator, 65_432_100_000_000);
    defer allocator.free(s1);
    try testing.expectEqualStrings("65432.100000000", s1);

    const s2 = try fixedToDecimalString(allocator, 1_500_000_000);
    defer allocator.free(s2);
    try testing.expectEqualStrings("1.500000000", s2);

    const s3 = try fixedToDecimalString(allocator, 1_000_000_000);
    defer allocator.free(s3);
    try testing.expectEqualStrings("1.000000000", s3);

    const s4 = try fixedToDecimalString(allocator, 0);
    defer allocator.free(s4);
    try testing.expectEqualStrings("0", s4);
}
