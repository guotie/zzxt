# zzxt — Zig 0.16 Crypto Exchange SDK (CCXT equivalent)

## Context

Build a Zig 0.16 library that provides a unified interface to multiple cryptocurrency exchanges (Binance, OKX, Bybit, etc.), mirroring CCXT's architecture. The repo is currently empty. Target users are Zig developers building trading bots, arbitrage systems, or market data tools who want CCXT-style exchange abstraction with Zig's performance and safety.

## Core Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Polymorphism | **Vtable** (like `std.mem.Allocator`) | Runtime dispatch, heterogeneous exchange collections, familiar Zig pattern |
| Numbers | **`u64` fixed-point** (×10^9) | Avoids floating-point errors; prices/amounts stored as `u64` with implicit 9 decimal places. E.g. `1.5 BTC` = `1_500_000_000`. Parsing: `decimalStringToFixed(s) → u64`. |
| HTTP | **`std.http.Client`** (stdlib) | Zig 0.16 native, async DNS, TLS built-in, zero deps |
| WebSocket | **Phase 2** | REST first to prove architecture, WS later via `websocket.zig` |
| I/O model | **Synchronous/blocking** | `std.http.Client` is blocking from caller perspective; async comes later |
| Memory | **ArenaAllocator for request-scoped temps**, caller owns returned structs | Clean lifetime model, no hidden allocations |

## Project Structure

```
zzxt/
  build.zig
  build.zig.zon
  src/
    root.zig                    # Public API re-exports
    Exchange.zig                # VTable + unified interface
    types/
      root.zig                  # Re-exports all types
      Market.zig
      Ticker.zig
      OrderBook.zig
      Trade.zig
      Order.zig
      Balance.zig
      OHLCV.zig
      Position.zig
      Transaction.zig
      Fee.zig
    errors.zig                  # Error hierarchy
    http_client.zig             # HTTP wrapper over std.http.Client
    signing.zig                 # HMAC-SHA256, SHA256, Ed25519 utilities
    rate_limiter.zig            # Token bucket rate limiter
    json_utils.zig              # JSON parsing helpers
    exchanges/
      binance/
        Binance.zig             # Concrete exchange implementation
        types.zig               # Binance-specific response structs
        signing.zig             # Binance request signing
        parsing.zig             # Raw JSON -> unified types
  examples/
    fetch_ticker.zig            # Basic usage example
```

## Phase 1: Foundation (~10 files)

### 1.1 `build.zig` + `build.zig.zon`

Standard Zig 0.16 library build. Expose `zzxt` as a module via `b.addModule()`. Test step runs all `_test.zig` files.

### 1.2 `src/errors.zig` — Error Hierarchy

```zig
pub const Error = error{
    // Exchange errors
    AuthenticationError,
    PermissionDenied,
    BadRequest,
    BadSymbol,
    InsufficientFunds,
    InvalidOrder,
    OrderNotFound,
    NotSupported,
    // Network errors
    NetworkError,
    DDoSProtection,
    RateLimitExceeded,
    ExchangeNotAvailable,
    RequestTimeout,
    // Response errors
    BadResponse,
    NullResponse,
};
```

### 1.3 `src/types/*.zig` — Unified Data Structures

All types include an `info: ?std.json.Value` field for raw exchange data.

**Numeric convention:** All prices, amounts, volumes, and costs use `u64` fixed-point with 9 implicit decimal places (×10^9). E.g. `1.5 BTC` = `1_500_000_000`, `$65432.10` = `65_432_100_000_000`. This avoids floating-point rounding errors in financial calculations.

```zig
// types/root.zig — shared alias
/// Fixed-point value: u64 with 9 implicit decimal places (×10^9).
pub const Fixed = u64;
pub const FIXED_SCALE: u64 = 1_000_000_000;

// Market.zig
pub const Market = struct {
    id: []const u8,         // exchange-specific ID
    symbol: []const u8,     // "BTC/USDT"
    base: []const u8,       // "BTC"
    quote: []const u8,      // "USDT"
    active: bool,
    type: enum { spot, margin, swap, future, option },
    spot: bool, swap: bool, future: bool, option: bool,
    precision: struct { amount: u8, price: u8 },
    limits: struct {
        amount: ?struct { min: ?Fixed, max: ?Fixed },
        price: ?struct { min: ?Fixed, max: ?Fixed },
        cost: ?struct { min: ?Fixed, max: ?Fixed },
    },
    taker: ?Fixed,
    maker: ?Fixed,
    info: ?std.json.Value,
};

// Ticker.zig
pub const Ticker = struct {
    symbol: []const u8,
    timestamp: ?i64,
    high: ?Fixed, low: ?Fixed,
    bid: ?Fixed, bid_volume: ?Fixed,
    ask: ?Fixed, ask_volume: ?Fixed,
    vwap: ?Fixed, open: ?Fixed, close: ?Fixed,
    last: ?Fixed, previous_close: ?Fixed,
    change: ?Fixed, percentage: ?Fixed,
    base_volume: ?Fixed, quote_volume: ?Fixed,
    info: ?std.json.Value,
};

// OrderBook.zig
pub const Level = struct { price: Fixed, amount: Fixed };
pub const OrderBook = struct {
    symbol: []const u8,
    bids: []const Level,
    asks: []const Level,
    timestamp: ?i64,
    nonce: ?i64,
    info: ?std.json.Value,
};

// OHLCV.zig
pub const OHLCV = struct {
    timestamp: i64,
    open: Fixed, high: Fixed, low: Fixed, close: Fixed,
    volume: Fixed,
};

// Trade.zig
pub const Trade = struct {
    id: ?[]const u8, symbol: []const u8,
    timestamp: ?i64, side: enum { buy, sell },
    type: ?enum { limit, market },
    price: Fixed, amount: Fixed, cost: ?Fixed,
    fee: ?Fee, info: ?std.json.Value,
};

// Order.zig
pub const Order = struct {
    id: []const u8, symbol: []const u8,
    status: enum { open, closed, canceled },
    type: ?enum { limit, market },
    side: enum { buy, sell },
    price: ?Fixed, amount: Fixed,
    filled: Fixed, remaining: Fixed, cost: ?Fixed,
    average: ?Fixed, fee: ?Fee,
    timestamp: ?i64,
    info: ?std.json.Value,
};

// Fee.zig
pub const Fee = struct { currency: ?[]const u8, cost: Fixed, rate: ?Fixed };

// Balance.zig
pub const Balance = struct { free: Fixed, used: Fixed, total: Fixed };
pub const Balances = struct {
    entries: std.StringHashMap(Balance),
    info: ?std.json.Value,
};
```

### 1.4 `src/Exchange.zig` — VTable Polymorphism Core

```zig
pub const VTable = struct {
    // Lifecycle
    deinit: *const fn (ctx: *anyopaque) void,
    describe: *const fn (ctx: *anyopaque) ExchangeDescription,

    // Public API
    fetch_markets: *const fn (ctx: *anyopaque, allocator: Allocator) Errors![]Market,
    fetch_ticker: *const fn (ctx: *anyopaque, allocator: Allocator, symbol: []const u8) Errors!Ticker,
    fetch_tickers: *const fn (ctx: *anyopaque, allocator: Allocator, symbols: ?[]const []const u8) Errors![]Ticker,
    fetch_order_book: *const fn (ctx: *anyopaque, allocator: Allocator, symbol: []const u8, limit: ?usize) Errors!OrderBook,
    fetch_ohlcv: *const fn (ctx: *anyopaque, allocator: Allocator, symbol: []const u8, timeframe: []const u8, since: ?i64, limit: ?usize) Errors![]OHLCV,
    fetch_trades: *const fn (ctx: *anyopaque, allocator: Allocator, symbol: []const u8, since: ?i64, limit: ?usize) Errors![]Trade,

    // Private API
    fetch_balance: *const fn (ctx: *anyopaque, allocator: Allocator) Errors!Balances,
    create_order: *const fn (ctx: *anyopaque, allocator: Allocator, symbol: []const u8, order_type: OrderType, side: Side, amount: Fixed, price: ?Fixed) Errors!Order,
    cancel_order: *const fn (ctx: *anyopaque, allocator: Allocator, id: []const u8, symbol: ?[]const u8) Errors!Order,
    fetch_order: *const fn (ctx: *anyopaque, allocator: Allocator, id: []const u8, symbol: ?[]const u8) Errors!Order,
    fetch_open_orders: *const fn (ctx: *anyopaque, allocator: Allocator, symbol: ?[]const u8) Errors![]Order,
};

pub const Exchange = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    // Inline wrapper methods that delegate to vtable
    pub fn deinit(self: Exchange) void { self.vtable.deinit(self.ptr); }
    pub fn fetchTicker(self: Exchange, allocator: Allocator, symbol: []const u8) Errors!Ticker { ... }
    pub fn fetchOrderBook(self: Exchange, allocator: Allocator, symbol: []const u8, limit: ?usize) Errors!OrderBook { ... }
    // ... etc for all methods
};
```

### 1.5 `src/json_utils.zig` — Parsing Helpers

```zig
/// Convert a decimal string (e.g. "65432.10", "0.000001") to Fixed (u64 × 10^9).
/// Returns error.Overflow if the value exceeds u64 range.
pub fn decimalStringToFixed(s: []const u8) !Fixed { ... }

/// Convert a Fixed value back to a decimal string. Caller owns memory.
pub fn fixedToDecimalString(allocator: Allocator, value: Fixed) ![]u8 { ... }

/// Parse a JSON string field as Fixed. Handles Binance-style string prices.
pub fn parseFixedField(json: std.json.Value, field: []const u8) !?Fixed { ... }
```

### 1.6 `src/http_client.zig` — HTTP Wrapper

```zig
pub const HttpClient = struct {
    client: std.http.Client,
    allocator: Allocator,

    pub fn init(allocator: Allocator, io: std.Io) HttpClient { ... }
    pub fn deinit(self: *HttpClient) void { ... }

    pub fn get(self: *HttpClient, url: []const u8, headers: ?[]const std.http.Header) ![]u8 { ... }
    pub fn post(self: *HttpClient, url: []const u8, body: []const u8, headers: ?[]const std.http.Header) ![]u8 { ... }

    // Returns heap-allocated response body. Caller owns memory.
    fn request(self: *HttpClient, method: std.http.Method, url: []const u8, body: ?[]const u8, headers: ?[]const std.http.Header) ![]u8 { ... }
};
```

### 1.7 `src/signing.zig` — Crypto Utilities

```zig
pub fn hmacSha256(out: *[32]u8, message: []const u8, key: []const u8) void;
pub fn sha256Hex(allocator: Allocator, data: []const u8) ![]u8;
pub fn hmacSha256Hex(allocator: Allocator, message: []const u8, key: []const u8) ![]u8;
```

### 1.8 `src/rate_limiter.zig` — Token Bucket

```zig
pub const RateLimiter = struct {
    capacity: f64,
    tokens: f64,
    refill_rate: f64,  // tokens per second
    last_refill: i64,

    pub fn init(rate_limit_ms: u32) RateLimiter { ... }
    pub fn acquire(self: *RateLimiter) void { ... }  // blocks until tokens available
};
```

### 1.9 `src/root.zig` — Public API

```zig
pub const Exchange = @import("Exchange.zig").Exchange;
pub const types = @import("types/root.zig");
pub const errors = @import("errors.zig");
pub const Binance = @import("exchanges/binance/Binance.zig");

// Re-export types at top level for convenience
pub const Ticker = types.Ticker;
pub const OrderBook = types.OrderBook;
// ... etc
```

**Phase 1 Verification:** `zig build test` passes. All types compile. `Exchange` vtable pattern compiles with a mock implementation.

---

## Phase 2: First Exchange — Binance (~4 files)

### 2.1 `src/exchanges/binance/types.zig` — Binance Response Structs

Raw JSON response types matching Binance API exactly:

```zig
pub const TickerResponse = struct {
    symbol: []const u8,
    priceChange: []const u8,
    priceChangePercent: []const u8,
    weightedAvgPrice: []const u8,
    lastPrice: []const u8,
    // ... all Binance 24hr ticker fields
};

pub const OrderBookResponse = struct {
    lastUpdateId: i64,
    bids: [][]const [2][]const u8,  // [[price, qty], ...]
    asks: [][]const [2][]const u8,
};

pub const KlineResponse = []const std.json.Value;  // array of mixed-type arrays
```

### 2.2 `src/exchanges/binance/signing.zig` — Binance Auth

```zig
pub const Credentials = struct {
    api_key: []const u8,
    secret: []const u8,
};

pub fn signQuery(allocator: Allocator, credentials: Credentials, query: []const u8) ![]u8;
// Returns "timestamp=...&signature=..." appended to query
```

### 2.3 `src/exchanges/binance/parsing.zig` — Response Parsers

Binance returns prices/amounts as **strings** (e.g. `"65432.10"`). All parsers call `decimalStringToFixed()` to convert to `u64`.

```zig
pub fn parseTicker(symbol: []const u8, json: TickerResponse) !Ticker;
pub fn parseOrderBook(json: OrderBookResponse) !OrderBook;
pub fn parseOHLCV(json: std.json.Value) !OHLCV;
pub fn parseTrade(json: std.json.Value) !Trade;
pub fn parseMarkets(json: std.json.Value) ![]Market;
pub fn parseBalance(json: std.json.Value) !Balances;
pub fn parseOrder(json: std.json.Value) !Order;
```

Example: Binance ticker `"lastPrice": "65432.10"` → `last: 65_432_100_000_000` (Fixed).

### 2.4 `src/exchanges/binance/Binance.zig` — Exchange Implementation

```zig
pub const Binance = struct {
    http: HttpClient,
    rate_limiter: RateLimiter,
    credentials: ?Credentials,
    allocator: Allocator,

    pub fn init(allocator: Allocator, io: std.Io, config: Config) !Exchange {
        const self = try allocator.create(Binance);
        self.* = .{
            .http = HttpClient.init(allocator, io),
            .rate_limiter = RateLimiter.init(1200),  // Binance: 1200ms
            .credentials = config.credentials,
            .allocator = allocator,
        };
        return .{ .ptr = self, .vtable = &vtable };
    }

    // Internal implementation methods
    fn fetchMarketsImpl(ctx: *anyopaque, allocator: Allocator) Errors![]Market { ... }
    fn fetchTickerImpl(ctx: *anyopaque, allocator: Allocator, symbol: []const u8) Errors!Ticker { ... }
    // ... etc

    const vtable = VTable{
        .deinit = deinitImpl,
        .describe = describeImpl,
        .fetch_markets = fetchMarketsImpl,
        .fetch_ticker = fetchTickerImpl,
        // ...
    };
};
```

**Binance API endpoints to implement:**
- `GET /api/v3/exchangeInfo` → fetchMarkets
- `GET /api/v3/ticker/24hr` → fetchTicker/fetchTickers
- `GET /api/v3/depth` → fetchOrderBook
- `GET /api/v3/klines` → fetchOHLCV
- `GET /api/v3/trades` → fetchTrades
- `GET /api/v3/account` → fetchBalance (signed)
- `POST /api/v3/order` → createOrder (signed)
- `GET /api/v3/order` → fetchOrder (signed)
- `DELETE /api/v3/order` → cancelOrder (signed)
- `GET /api/v3/openOrders` → fetchOpenOrders (signed)

**Phase 2 Verification:** Write a `fetch_ticker.zig` example that fetches BTC/USDT ticker from Binance public API and prints the result. Run with `zig build run -- fetch_ticker`.

---

## Phase 3: More Exchanges (2 files)

### 3.1 OKX (`src/exchanges/okx/Okx.zig`)

Same pattern as Binance. Key differences:
- Different base URL (`https://www.okx.com`)
- Different response format (wrapped in `{"code":"0","data":[...]}`)
- Signing: HMAC-SHA256 of `timestamp+method+requestPath+body`
- Rate limit: 20 requests/2s

### 3.2 Bybit (`src/exchanges/bybit/Bybit.zig`)

- Base URL: `https://api.bybit.com`
- V5 API (unified)
- Signing: HMAC-SHA256 of `apiKey+timestamp+recvWindow+queryString`
- Rate limit: 120 requests/min

**Phase 3 Verification:** Same ticker example works with OKX and Bybit by changing one line. All three exchanges return the same `Ticker` struct.

---

## Phase 4: WebSocket (2 files, future)

Defer until REST is solid. Will use `websocket.zig` dependency.

- `src/WebSocket.zig` — unified WS client with `watchTicker`, `watchOrderBook`, `watchTrades`
- `src/exchanges/binance/BinanceWs.zig` — Binance WebSocket streams

---

## Phase 5: Polish

- Comprehensive tests with `std.testing.allocator` for leak detection
- `examples/` directory with fetch_ticker, create_order, multi_exchange
- README with usage examples
- CI (GitHub Actions: `zig build test` on Linux/macOS/Windows)

---

## Implementation Order

1. `build.zig` + `build.zig.zon` (scaffold)
2. `src/errors.zig` (error set)
3. `src/types/*.zig` (all data structures with Fixed type)
4. `src/json_utils.zig` (decimalStringToFixed, fixedToDecimalString)
5. `src/signing.zig` (crypto utils)
6. `src/rate_limiter.zig` (token bucket)
7. `src/http_client.zig` (HTTP wrapper)
8. `src/Exchange.zig` (vtable core)
9. `src/root.zig` (public API)
10. `src/exchanges/binance/types.zig` (Binance response types)
11. `src/exchanges/binance/signing.zig` (Binance auth)
12. `src/exchanges/binance/parsing.zig` (response parsers: string → Fixed)
13. `src/exchanges/binance/Binance.zig` (exchange impl)
14. `examples/fetch_ticker.zig` (end-to-end test)

## Verification

- `zig build test` — all unit tests pass, no memory leaks
- `zig build run -- examples/fetch_ticker.zig` — fetches live BTC/USDT ticker from Binance
- Manual: instantiate all 3 exchanges, fetch same ticker, compare struct shapes
