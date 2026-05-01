//! Metrics collection for Zig.
//!
//! Counters, gauges, and histograms with Prometheus-compatible exposition.
//! Registry for named metrics.

const std = @import("std");

/// A monotonically increasing counter.
pub const Counter = struct {
    value: u64 = 0,

    /// Increment by 1.
    pub fn inc(self: *Counter) void {
        self.value += 1;
    }

    /// Add a value.
    pub fn add(self: *Counter, n: u64) void {
        self.value += n;
    }

    /// Get current value.
    pub fn get(self: *const Counter) u64 {
        return self.value;
    }

    /// Reset to zero (useful for tests).
    pub fn reset(self: *Counter) void {
        self.value = 0;
    }
};

/// A value that can go up and down.
pub const Gauge = struct {
    value: f64 = 0,

    pub fn set(self: *Gauge, v: f64) void {
        self.value = v;
    }

    pub fn inc(self: *Gauge) void {
        self.value += 1;
    }

    pub fn dec(self: *Gauge) void {
        self.value -= 1;
    }

    pub fn add(self: *Gauge, v: f64) void {
        self.value += v;
    }

    pub fn sub(self: *Gauge, v: f64) void {
        self.value -= v;
    }

    pub fn get(self: *const Gauge) f64 {
        return self.value;
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

test "Counter add and get" {
    var c: Counter = .{};
    c.add(10);
    c.add(5);
    try std.testing.expectEqual(@as(u64, 15), c.get());
}

test "Counter reset" {
    var c: Counter = .{};
    c.inc();
    c.inc();
    c.reset();
    try std.testing.expectEqual(@as(u64, 0), c.get());
}

test "Gauge add and sub" {
    var g: Gauge = .{};
    g.set(10.0);
    g.add(5.0);
    g.sub(3.0);
    try std.testing.expectEqual(@as(f64, 12.0), g.get());
}

test "Histogram mean with observations" {
    var h: Histogram = .{};
    h.observe(10.0);
    h.observe(20.0);
    try std.testing.expectEqual(@as(f64, 15.0), h.mean());
}

test "Registry writePrometheus" {
    var reg: Registry(10) = .{};
    const c = reg.counter("requests").?;
    c.inc();
    var buf: [256]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    try reg.writePrometheus(stream.writer());
    const output = stream.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, "requests") != null);
}
