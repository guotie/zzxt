const std = @import("std");
const types = @import("../../types/root.zig");
const json_utils = @import("../../json_utils.zig");
const binance_types = @import("types.zig");

const Fixed = types.Fixed;
const FIXED_SCALE = types.FIXED_SCALE;

pub fn parseTicker(symbol: []const u8, json: binance_types.TickerResponse) !types.Ticker {
    return types.Ticker{
        .symbol = symbol,
        .timestamp = json.closeTime,
        .high = try json_utils.decimalStringToFixed(json.highPrice),
        .low = try json_utils.decimalStringToFixed(json.lowPrice),
        .bid = try json_utils.decimalStringToFixed(json.bidPrice),
        .bid_volume = try json_utils.decimalStringToFixed(json.bidQty),
        .ask = try json_utils.decimalStringToFixed(json.askPrice),
        .ask_volume = try json_utils.decimalStringToFixed(json.askQty),
        .vwap = try json_utils.decimalStringToFixed(json.weightedAvgPrice),
        .open = try json_utils.decimalStringToFixed(json.openPrice),
        .close = null,
        .last = try json_utils.decimalStringToFixed(json.lastPrice),
        .previous_close = null,
        .change = try json_utils.decimalStringToFixed(json.priceChange),
        .percentage = try json_utils.decimalStringToFixed(json.priceChangePercent),
        .base_volume = try json_utils.decimalStringToFixed(json.volume),
        .quote_volume = try json_utils.decimalStringToFixed(json.quoteVolume),
        .info = null,
    };
}

pub fn parseOrderBook(json: binance_types.OrderBookResponse, allocator: std.mem.Allocator) !types.OrderBook {
    var bids = try std.ArrayList(types.Level).initCapacity(allocator, json.bids.len);
    errdefer bids.deinit(allocator);

    for (json.bids) |level| {
        if (level.len >= 2) {
            try bids.append(allocator, .{
                .price = try json_utils.decimalStringToFixed(level[0]),
                .amount = try json_utils.decimalStringToFixed(level[1]),
            });
        }
    }

    var asks = try std.ArrayList(types.Level).initCapacity(allocator, json.asks.len);
    errdefer asks.deinit(allocator);

    for (json.asks) |level| {
        if (level.len >= 2) {
            try asks.append(allocator, .{
                .price = try json_utils.decimalStringToFixed(level[0]),
                .amount = try json_utils.decimalStringToFixed(level[1]),
            });
        }
    }

    return types.OrderBook{
        .symbol = "",
        .bids = try bids.toOwnedSlice(allocator),
        .asks = try asks.toOwnedSlice(allocator),
        .timestamp = null,
        .nonce = json.lastUpdateId,
        .info = null,
    };
}

pub fn parseOHLCV(json: std.json.Value) !types.OHLCV {
    const arr = json.array.items;
    if (arr.len < 6) return error.BadResponse;

    return types.OHLCV{
        .timestamp = @intCast(arr[0].integer),
        .open = try json_utils.decimalStringToFixed(arr[1].string),
        .high = try json_utils.decimalStringToFixed(arr[2].string),
        .low = try json_utils.decimalStringToFixed(arr[3].string),
        .close = try json_utils.decimalStringToFixed(arr[4].string),
        .volume = try json_utils.decimalStringToFixed(arr[5].string),
    };
}

pub fn parseTrade(json: std.json.Value) !types.Trade {
    const obj = json.object;

    return types.Trade{
        .id = obj.get("id").?.string,
        .symbol = "",
        .timestamp = @intCast(obj.get("time").?.integer),
        .side = if (obj.get("isBuyerMaker").?.bool) .sell else .buy,
        .type = null,
        .price = try json_utils.decimalStringToFixed(obj.get("price").?.string),
        .amount = try json_utils.decimalStringToFixed(obj.get("qty").?.string),
        .cost = try json_utils.decimalStringToFixed(obj.get("quoteQty").?.string),
        .fee = null,
        .info = json,
    };
}

pub fn parseMarkets(json: std.json.Value, allocator: std.mem.Allocator) ![]types.Market {
    const symbols = json.object.get("symbols").?.array.items;
    var markets = try std.ArrayList(types.Market).initCapacity(allocator, symbols.len);
    errdefer markets.deinit(allocator);

    for (symbols) |sym| {
        const obj = sym.object;
        const status = obj.get("status").?.string;
        const active = std.mem.eql(u8, status, "TRADING");

        const symbol_str = obj.get("symbol").?.string;
        const base = obj.get("baseAsset").?.string;
        const quote = obj.get("quoteAsset").?.string;

        // Build "BTC/USDT" format
        const symbol = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ base, quote });

        try markets.append(allocator, .{
            .id = symbol_str,
            .symbol = symbol,
            .base = base,
            .quote = quote,
            .active = active,
            .type = .spot,
            .spot = true,
            .swap = false,
            .future = false,
            .option = false,
            .precision = .{
                .amount = @intCast(obj.get("baseAssetPrecision").?.integer),
                .price = @intCast(obj.get("quoteAssetPrecision").?.integer),
            },
            .limits = .{
                .amount = null,
                .price = null,
                .cost = null,
            },
            .taker = null,
            .maker = null,
            .info = sym,
        });
    }

    return try markets.toOwnedSlice(allocator);
}

pub fn parseBalance(json: std.json.Value, allocator: std.mem.Allocator) !types.Balances {
    const obj = json.object;
    const balances_arr = obj.get("balances").?.array.items;

    var entries = std.StringHashMap(types.Balance).init(allocator);
    errdefer entries.deinit();

    for (balances_arr) |bal| {
        const bal_obj = bal.object;
        const asset = bal_obj.get("asset").?.string;
        const free = try json_utils.decimalStringToFixed(bal_obj.get("free").?.string);
        const locked = try json_utils.decimalStringToFixed(bal_obj.get("locked").?.string);

        if (free > 0 or locked > 0) {
            try entries.put(asset, .{
                .free = free,
                .used = locked,
                .total = free + locked,
            });
        }
    }

    return types.Balances{
        .entries = entries,
        .info = json,
    };
}

pub fn parseOrder(json: std.json.Value) !types.Order {
    const obj = json.object;

    const status_str = obj.get("status").?.string;
    const status: types.OrderStatus = switch (status_str[0]) {
        'N' => .open, // NEW
        'F' => .open, // FILLED -> closed
        'C' => .canceled, // CANCELED
        'P' => .open, // PARTIALLY_FILLED
        else => .open,
    };

    const side_str = obj.get("side").?.string;
    const side: types.Side = if (std.mem.eql(u8, side_str, "BUY")) .buy else .sell;

    const type_str = obj.get("type").?.string;
    const order_type: types.OrderType = if (std.mem.eql(u8, type_str, "LIMIT")) .limit else .market;

    const price = try json_utils.parseFixedField(json, "price");
    const amount = try json_utils.decimalStringToFixed(obj.get("origQty").?.string);
    const filled = try json_utils.decimalStringToFixed(obj.get("executedQty").?.string);

    return types.Order{
        .id = obj.get("orderId").?.string,
        .symbol = obj.get("symbol").?.string,
        .status = status,
        .type = order_type,
        .side = side,
        .price = price,
        .amount = amount,
        .filled = filled,
        .remaining = amount - filled,
        .cost = null,
        .average = null,
        .fee = null,
        .timestamp = @intCast(obj.get("time").?.integer),
        .info = json,
    };
}
