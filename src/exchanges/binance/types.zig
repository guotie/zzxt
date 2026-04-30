const std = @import("std");

pub const TickerResponse = struct {
    symbol: []const u8,
    priceChange: []const u8,
    priceChangePercent: []const u8,
    weightedAvgPrice: []const u8,
    lastPrice: []const u8,
    lastQty: []const u8,
    bidPrice: []const u8,
    bidQty: []const u8,
    askPrice: []const u8,
    askQty: []const u8,
    openPrice: []const u8,
    highPrice: []const u8,
    lowPrice: []const u8,
    volume: []const u8,
    quoteVolume: []const u8,
    openTime: i64,
    closeTime: i64,
    firstId: i64,
    lastId: i64,
    count: i64,
};

pub const OrderBookResponse = struct {
    lastUpdateId: i64,
    bids: []const []const []const u8,
    asks: []const []const []const u8,
};

pub const KlineResponse = []const []const std.json.Value;

pub const TradeResponse = struct {
    id: i64,
    price: []const u8,
    qty: []const u8,
    quoteQty: []const u8,
    time: i64,
    isBuyerMaker: bool,
    isBestMatch: bool,
};

pub const ExchangeInfoResponse = struct {
    timezone: []const u8,
    serverTime: i64,
    symbols: []const SymbolInfo,
};

pub const SymbolInfo = struct {
    symbol: []const u8,
    status: []const u8,
    baseAsset: []const u8,
    quoteAsset: []const u8,
    baseAssetPrecision: u8,
    quoteAssetPrecision: u8,
    orderTypes: []const []const u8,
    filters: []const std.json.Value,
    permissions: []const []const u8,
};
