//! Metrics collection for Zig.
//!
//! Counters, gauges, and histograms with Prometheus-compatible exposition.
//! Registry for named metrics.

const std = @import("std");

/// A monotonically increasing counter. Thread-safe: increments are atomic, so
/// concurrent handlers scraping the same counter cannot lose updates.
pub const Counter = struct {
    value: std.atomic.Value(u64) = .{ .raw = 0 },

    /// Increment by 1.
    pub fn inc(self: *Counter) void {
        _ = self.value.fetchAdd(1, .monotonic);
    }

    /// Add a value.
    pub fn add(self: *Counter, n: u64) void {
        _ = self.value.fetchAdd(n, .monotonic);
    }

    /// Get current value.
    pub fn get(self: *const Counter) u64 {
        return self.value.load(.monotonic);
    }

    /// Reset to zero (useful for tests).
    pub fn reset(self: *Counter) void {
        self.value.store(0, .monotonic);
    }
};

/// A value that can go up and down. Thread-safe: the f64 is stored as its bit
/// pattern in an atomic word, so set/get are lock-free and add/sub use a
/// compare-and-swap loop rather than a racy read-modify-write.
pub const Gauge = struct {
    bits: std.atomic.Value(u64) = .{ .raw = 0 },

    pub fn set(self: *Gauge, v: f64) void {
        self.bits.store(@bitCast(v), .monotonic);
    }

    fn rmw(self: *Gauge, delta: f64) void {
        var cur = self.bits.load(.monotonic);
        while (true) {
            const next: u64 = @bitCast(@as(f64, @bitCast(cur)) + delta);
            if (self.bits.cmpxchgWeak(cur, next, .monotonic, .monotonic)) |actual| {
                cur = actual;
            } else break;
        }
    }

    pub fn inc(self: *Gauge) void {
        self.rmw(1);
    }

    pub fn dec(self: *Gauge) void {
        self.rmw(-1);
    }

    pub fn add(self: *Gauge, v: f64) void {
        self.rmw(v);
    }

    pub fn sub(self: *Gauge, v: f64) void {
        self.rmw(-v);
    }

    pub fn get(self: *const Gauge) f64 {
        return @bitCast(self.bits.load(.monotonic));
    }
};

/// A histogram for tracking value distributions.
pub const Histogram = struct {
    count: u64 = 0,
    sum: f64 = 0,
    min: f64 = std.math.floatMax(f64),
    max: f64 = 0,

    pub fn observe(self: *Histogram, value: f64) void {
        self.count += 1;
        self.sum += value;
        if (value < self.min) self.min = value;
        if (value > self.max) self.max = value;
    }

    pub fn mean(self: *const Histogram) f64 {
        if (self.count == 0) return 0;
        return self.sum / @as(f64, @floatFromInt(self.count));
    }

    pub fn isEmpty(self: *const Histogram) bool {
        return self.count == 0;
    }
};

/// A Prometheus-conformant cumulative histogram with fixed upper bounds.
///
/// Unlike `Histogram` (which only tracks count/sum/min/max), this emits real
/// `name_bucket{le="..."}` series through `+Inf`, plus `_sum` and `_count`, so
/// `histogram_quantile()` works against a scrape. Bucket counts and the sum are
/// atomic, so it is safe to observe from multiple request handlers at once.
///
/// `upper_bounds` must be ascending. Pass them as a comptime slice, e.g.
/// `BucketedHistogram(&.{ 0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10 })`.
pub fn BucketedHistogram(comptime upper_bounds: []const f64) type {
    return struct {
        const Self = @This();
        pub const bounds = upper_bounds;

        comptime {
            for (upper_bounds[1..], 0..) |b, i| {
                if (b <= upper_bounds[i]) @compileError("BucketedHistogram bounds must be strictly ascending");
            }
        }

        buckets: [upper_bounds.len]std.atomic.Value(u64) = @splat(.{ .raw = 0 }),
        inf_count: std.atomic.Value(u64) = .{ .raw = 0 },
        sum_bits: std.atomic.Value(u64) = .{ .raw = 0 },
        total: std.atomic.Value(u64) = .{ .raw = 0 },

        pub fn observe(self: *Self, value: f64) void {
            _ = self.total.fetchAdd(1, .monotonic);
            var cur = self.sum_bits.load(.monotonic);
            while (true) {
                const next: u64 = @bitCast(@as(f64, @bitCast(cur)) + value);
                if (self.sum_bits.cmpxchgWeak(cur, next, .monotonic, .monotonic)) |actual| {
                    cur = actual;
                } else break;
            }
            // Store non-cumulatively in the first bucket whose bound covers the
            // value; the cumulative sum is formed at render time.
            inline for (upper_bounds, 0..) |b, i| {
                if (value <= b) {
                    _ = self.buckets[i].fetchAdd(1, .monotonic);
                    return;
                }
            }
            _ = self.inf_count.fetchAdd(1, .monotonic);
        }

        pub fn count(self: *const Self) u64 {
            return self.total.load(.monotonic);
        }

        pub fn sum(self: *const Self) f64 {
            return @bitCast(self.sum_bits.load(.monotonic));
        }

        /// Emit the `# TYPE`, cumulative `_bucket{le=...}` lines (including
        /// `+Inf`), `_sum` and `_count` for this histogram under `name`.
        pub fn writePrometheus(self: *const Self, name: []const u8, writer: anytype) !void {
            try writer.print("# TYPE {s} histogram\n", .{name});
            var cumulative: u64 = 0;
            inline for (upper_bounds, 0..) |b, i| {
                cumulative += self.buckets[i].load(.monotonic);
                try writer.print("{s}_bucket{{le=\"{d}\"}} {d}\n", .{ name, b, cumulative });
            }
            cumulative += self.inf_count.load(.monotonic);
            try writer.print("{s}_bucket{{le=\"+Inf\"}} {d}\n", .{ name, cumulative });
            try writer.print("{s}_sum {d}\n", .{ name, self.sum() });
            try writer.print("{s}_count {d}\n", .{ name, cumulative });
        }
    };
}

/// A registry of named metrics.
pub fn Registry(comptime max_metrics: usize) type {
    return struct {
        counters: [max_metrics]?Counter = .{null} ** max_metrics,
        gauges: [max_metrics]?Gauge = .{null} ** max_metrics,
        histograms: [max_metrics]?Histogram = .{null} ** max_metrics,
        counter_names: [max_metrics][]const u8 = .{""} ** max_metrics,
        gauge_names: [max_metrics][]const u8 = .{""} ** max_metrics,
        histogram_names: [max_metrics][]const u8 = .{""} ** max_metrics,
        counter_count: usize = 0,
        gauge_count: usize = 0,
        histogram_count: usize = 0,

        const Self = @This();

        pub fn counter(self: *Self, name: []const u8) ?*Counter {
            for (self.counter_names[0..self.counter_count], 0..) |n, i| {
                if (std.mem.eql(u8, n, name)) return &self.counters[i].?;
            }
            if (self.counter_count >= max_metrics) return null;
            self.counter_names[self.counter_count] = name;
            self.counters[self.counter_count] = .{};
            self.counter_count += 1;
            return &self.counters[self.counter_count - 1].?;
        }

        pub fn gauge(self: *Self, name: []const u8) ?*Gauge {
            for (self.gauge_names[0..self.gauge_count], 0..) |n, i| {
                if (std.mem.eql(u8, n, name)) return &self.gauges[i].?;
            }
            if (self.gauge_count >= max_metrics) return null;
            self.gauge_names[self.gauge_count] = name;
            self.gauges[self.gauge_count] = .{};
            self.gauge_count += 1;
            return &self.gauges[self.gauge_count - 1].?;
        }

        pub fn histogram(self: *Self, name: []const u8) ?*Histogram {
            for (self.histogram_names[0..self.histogram_count], 0..) |n, i| {
                if (std.mem.eql(u8, n, name)) return &self.histograms[i].?;
            }
            if (self.histogram_count >= max_metrics) return null;
            self.histogram_names[self.histogram_count] = name;
            self.histograms[self.histogram_count] = .{};
            self.histogram_count += 1;
            return &self.histograms[self.histogram_count - 1].?;
        }

        /// Format all metrics in Prometheus exposition format.
        pub fn writePrometheus(self: *Self, writer: anytype) !void {
            for (self.counter_names[0..self.counter_count], 0..) |name, i| {
                if (self.counters[i]) |c| {
                    try writer.print("# HELP {s} counter\n", .{name});
                    try writer.print("# TYPE {s} counter\n", .{name});
                    try writer.print("{s} {d}\n", .{ name, c.get() });
                }
            }
            for (self.gauge_names[0..self.gauge_count], 0..) |name, i| {
                if (self.gauges[i]) |g| {
                    try writer.print("# HELP {s} gauge\n", .{name});
                    try writer.print("# TYPE {s} gauge\n", .{name});
                    try writer.print("{s} {d}\n", .{ name, g.get() });
                }
            }
            for (self.histogram_names[0..self.histogram_count], 0..) |name, i| {
                if (self.histograms[i]) |h| {
                    try writer.print("# HELP {s} histogram\n", .{name});
                    try writer.print("# TYPE {s} histogram\n", .{name});
                    try writer.print("{s}_count {d}\n", .{ name, h.count });
                    try writer.print("{s}_sum {d}\n", .{ name, h.sum });
                    try writer.print("{s}_min {d}\n", .{ name, h.min });
                    try writer.print("{s}_max {d}\n", .{ name, h.max });
                }
            }
        }
    };
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "Counter basic operations" {
    var c: Counter = .{};
    try std.testing.expectEqual(@as(u64, 0), c.get());
    c.inc();
    c.inc();
    c.inc();
    try std.testing.expectEqual(@as(u64, 3), c.get());
    c.add(7);
    try std.testing.expectEqual(@as(u64, 10), c.get());
    c.reset();
    try std.testing.expectEqual(@as(u64, 0), c.get());
}

test "Gauge set and modify" {
    var g: Gauge = .{};
    g.set(42.5);
    try std.testing.expectEqual(@as(f64, 42.5), g.get());
    g.inc();
    try std.testing.expectEqual(@as(f64, 43.5), g.get());
    g.dec();
    try std.testing.expectEqual(@as(f64, 42.5), g.get());
    g.add(7.5);
    try std.testing.expectEqual(@as(f64, 50.0), g.get());
    g.sub(10.0);
    try std.testing.expectEqual(@as(f64, 40.0), g.get());
}

test "Gauge can go negative" {
    var g: Gauge = .{};
    g.dec();
    try std.testing.expectEqual(@as(f64, -1.0), g.get());
}

test "Histogram tracks distribution" {
    var h: Histogram = .{};
    h.observe(10);
    h.observe(20);
    h.observe(30);
    h.observe(40);
    h.observe(50);
    try std.testing.expectEqual(@as(u64, 5), h.count);
    try std.testing.expectEqual(@as(f64, 10), h.min);
    try std.testing.expectEqual(@as(f64, 50), h.max);
    try std.testing.expectApproxEqAbs(@as(f64, 30), h.mean(), 0.001);
}

test "Histogram empty state" {
    var h: Histogram = .{};
    try std.testing.expect(h.isEmpty());
    try std.testing.expectEqual(@as(u64, 0), h.count);
    try std.testing.expectEqual(@as(f64, 0), h.mean());
}

test "Histogram single observation" {
    var h: Histogram = .{};
    h.observe(42.0);
    try std.testing.expect(!h.isEmpty());
    try std.testing.expectEqual(@as(f64, 42.0), h.min);
    try std.testing.expectEqual(@as(f64, 42.0), h.max);
    try std.testing.expectEqual(@as(f64, 42.0), h.mean());
}

test "Counter is safe under concurrent increments" {
    var c: Counter = .{};
    const Worker = struct {
        fn run(counter: *Counter) void {
            for (0..10_000) |_| counter.inc();
        }
    };
    var threads: [4]std.Thread = undefined;
    for (&threads) |*t| t.* = try std.Thread.spawn(.{}, Worker.run, .{&c});
    for (threads) |t| t.join();
    // Without atomics this would lose updates to the read-modify-write race.
    try std.testing.expectEqual(@as(u64, 40_000), c.get());
}

test "Gauge atomic set and rmw" {
    var g: Gauge = .{};
    try std.testing.expectEqual(@as(f64, 0), g.get());
    g.set(42.5);
    try std.testing.expectEqual(@as(f64, 42.5), g.get());
    g.add(7.5);
    try std.testing.expectEqual(@as(f64, 50.0), g.get());
    g.sub(10.0);
    try std.testing.expectEqual(@as(f64, 40.0), g.get());
    g.dec();
    try std.testing.expectEqual(@as(f64, 39.0), g.get());
}

test "BucketedHistogram emits cumulative Prometheus buckets" {
    const H = BucketedHistogram(&.{ 1, 5, 10 });
    var h: H = .{};
    h.observe(0.5); // le=1
    h.observe(3); // le=5
    h.observe(50); // +Inf
    try std.testing.expectEqual(@as(u64, 3), h.count());
    try std.testing.expectApproxEqAbs(@as(f64, 53.5), h.sum(), 0.001);

    var buf: [512]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);
    try h.writePrometheus("lat", &writer);
    const out = writer.buffered();
    // cumulative: le=1 -> 1, le=5 -> 2, le=10 -> 2, +Inf -> 3
    try std.testing.expect(std.mem.indexOf(u8, out, "lat_bucket{le=\"1\"} 1") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "lat_bucket{le=\"5\"} 2") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "lat_bucket{le=\"10\"} 2") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "lat_bucket{le=\"+Inf\"} 3") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "lat_count 3") != null);
}

test "Registry stores named counters" {
    var reg: Registry(10) = .{};
    const c1 = reg.counter("requests").?;
    c1.inc();
    c1.inc();
    try std.testing.expectEqual(@as(u64, 2), c1.get());
    // Same name returns same counter
    const c2 = reg.counter("requests").?;
    try std.testing.expectEqual(@as(u64, 2), c2.get());
}

test "Registry stores multiple counters" {
    var reg: Registry(10) = .{};
    const req = reg.counter("requests").?;
    const errs = reg.counter("errors").?;
    req.add(100);
    errs.add(3);
    try std.testing.expectEqual(@as(u64, 100), req.get());
    try std.testing.expectEqual(@as(u64, 3), errs.get());
}

test "Registry stores named gauges" {
    var reg: Registry(10) = .{};
    const cpu = reg.gauge("cpu_percent").?;
    cpu.set(75.5);
    try std.testing.expectEqual(@as(f64, 75.5), cpu.get());
}

test "Registry stores histograms" {
    var reg: Registry(10) = .{};
    const lat = reg.histogram("latency_ms").?;
    lat.observe(10);
    lat.observe(20);
    lat.observe(30);
    try std.testing.expectEqual(@as(u64, 3), lat.count);
}

test "Registry returns null when full" {
    var reg: Registry(2) = .{};
    _ = reg.counter("a");
    _ = reg.counter("b");
    try std.testing.expect(reg.counter("c") == null);
}

test "Registry writePrometheus" {
    var reg: Registry(10) = .{};
    const c = reg.counter("requests").?;
    c.inc();
    var buf: [256]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);
    try reg.writePrometheus(&writer);
    const output = writer.buffered();
    try std.testing.expect(std.mem.indexOf(u8, output, "requests") != null);
}
