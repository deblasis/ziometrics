//! Metrics collection for Zig.

const std = @import("std");

/// A monotonically increasing counter.
pub const Counter = struct {
    value: u64 = 0,
    pub fn inc(self: *Counter) void {
        self.value += 1;
    }
    pub fn add(self: *Counter, n: u64) void {
        self.value += n;
    }
    pub fn get(self: *Counter) u64 {
        return self.value;
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
    pub fn get(self: *Gauge) f64 {
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
    pub fn mean(self: *Histogram) f64 {
        if (self.count == 0) return 0;
        return self.sum / @as(f64, @floatFromInt(self.count));
    }
};

/// A registry of named metrics.
pub fn Registry(comptime max_metrics: usize) type {
    return struct {
        counters: [max_metrics]?Counter = .{null} ** max_metrics,
        gauges: [max_metrics]?Gauge = .{null} ** max_metrics,
        counter_names: [max_metrics][]const u8 = .{""} ** max_metrics,
        gauge_names: [max_metrics][]const u8 = .{""} ** max_metrics,
        counter_count: usize = 0,
        gauge_count: usize = 0,

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
    };
}

test "Counter increments" {
    var c: Counter = .{};
    try std.testing.expectEqual(@as(u64, 0), c.get());
    c.inc();
    c.inc();
    try std.testing.expectEqual(@as(u64, 2), c.get());
    c.add(8);
    try std.testing.expectEqual(@as(u64, 10), c.get());
}

test "Gauge tracks value" {
    var g: Gauge = .{};
    g.set(42.5);
    try std.testing.expectEqual(@as(f64, 42.5), g.get());
    g.inc();
    try std.testing.expectEqual(@as(f64, 43.5), g.get());
    g.dec();
    try std.testing.expectEqual(@as(f64, 42.5), g.get());
}

test "Histogram tracks distribution" {
    var h: Histogram = .{};
    h.observe(10);
    h.observe(20);
    h.observe(30);
    try std.testing.expectEqual(@as(u64, 3), h.count);
    try std.testing.expectEqual(@as(f64, 10), h.min);
    try std.testing.expectEqual(@as(f64, 30), h.max);
    try std.testing.expectApproxEqAbs(@as(f64, 20), h.mean(), 0.001);
}

test "Registry stores named counters" {
    var reg: Registry(10) = .{};
    const c = reg.counter("requests").?;
    c.inc();
    c.inc();
    try std.testing.expectEqual(@as(u64, 2), c.get());
    // Same name returns same counter
    const c2 = reg.counter("requests").?;
    try std.testing.expectEqual(@as(u64, 2), c2.get());
}

test "Registry stores named gauges" {
    var reg: Registry(10) = .{};
    const g = reg.gauge("cpu").?;
    g.set(75.5);
    try std.testing.expectEqual(@as(f64, 75.5), g.get());
}
