const std = @import("std");
const zzxt = @import("zzxt");

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();

    std.debug.print("Initializing Binance exchange...\n", .{});

    const exchange = try zzxt.Binance.Binance.init(allocator, init.io, .{});
    defer exchange.deinit();

    std.debug.print("Fetching BTC/USDT ticker...\n", .{});

    const ticker = exchange.fetchTicker(allocator, "BTCUSDT") catch |err| {
        std.debug.print("Error fetching ticker: {}\n", .{err});
        return;
    };

    std.debug.print("\n=== BTC/USDT Ticker ===\n", .{});
    std.debug.print("Symbol: {s}\n", .{ticker.symbol});
    if (ticker.last) |last| {
        std.debug.print("Last price: {d}\n", .{last});
    }
    if (ticker.high) |high| {
        std.debug.print("24h high: {d}\n", .{high});
    }
    if (ticker.low) |low| {
        std.debug.print("24h low: {d}\n", .{low});
    }
    if (ticker.base_volume) |vol| {
        std.debug.print("24h volume: {d}\n", .{vol});
    }
    if (ticker.percentage) |pct| {
        std.debug.print("24h change: {d}%\n", .{pct});
    }
}
