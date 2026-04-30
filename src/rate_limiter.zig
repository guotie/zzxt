const std = @import("std");

pub const RateLimiter = struct {
    capacity: f64,
    tokens: f64,
    refill_rate: f64, // tokens per second
    last_refill: i64,

    pub fn init(rate_limit_ms: u32) RateLimiter {
        const refill_rate = 1000.0 / @as(f64, @floatFromInt(rate_limit_ms));
        return .{
            .capacity = 1.0,
            .tokens = 1.0,
            .refill_rate = refill_rate,
            .last_refill = @intCast(@as(u64, @bitCast(std.time.nanoTimestamp()))),
        };
    }

    pub fn acquire(self: *RateLimiter) void {
        self.refill();
        while (self.tokens < 1.0) {
            const deficit = 1.0 - self.tokens;
            const sleep_ns: u64 = @intFromFloat(deficit / self.refill_rate * 1_000_000_000.0);
            if (sleep_ns > 0) {
                std.time.sleep(sleep_ns);
            }
            self.refill();
        }
        self.tokens -= 1.0;
    }

    fn refill(self: *RateLimiter) void {
        const now: i64 = @intCast(@as(u64, @bitCast(std.time.nanoTimestamp())));
        const elapsed = @as(f64, @floatFromInt(now - self.last_refill)) / 1_000_000_000.0;
        if (elapsed > 0) {
            self.tokens = @min(self.capacity, self.tokens + elapsed * self.refill_rate);
            self.last_refill = now;
        }
    }
};

test "RateLimiter basic" {
    const testing = std.testing;
    var limiter = RateLimiter.init(100);
    limiter.acquire();
    try testing.expect(true);
}
