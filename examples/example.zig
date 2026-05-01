const std = @import("std");
const ziometrics = @import("ziometrics");

pub fn main() !void {
    std.debug.print("=== ziometrics example ===\n\n", .{});

    var reg: ziometrics.Registry(10) = .{};

    // Counters
    const requests = reg.counter("http_requests").?;
    const errors = reg.counter("http_errors").?;
    requests.inc();
    requests.inc();
    requests.inc();
    errors.add(1);

    // Gauges
    const cpu = reg.gauge("cpu_percent").?;
    cpu.set(72.5);

    // Histogram
    const latency = reg.histogram("latency_ms").?;
    latency.observe(10.5);
    latency.observe(25.0);
    latency.observe(8.3);
    latency.observe(42.1);

    std.debug.print("Counters:\n", .{});
    std.debug.print("  requests: {d}\n", .{requests.get()});
    std.debug.print("  errors:   {d}\n", .{errors.get()});
    std.debug.print("\nGauges:\n", .{});
    std.debug.print("  cpu:      {d:.1}%\n", .{cpu.get()});
    std.debug.print("\nHistogram:\n", .{});
    std.debug.print("  count={d} min={d:.1} max={d:.1} mean={d:.1}\n", .{
        latency.count, latency.min, latency.max, latency.mean(),
    });
}
