# ziometrics

Metrics collection for Zig. Counters, gauges, histograms with Prometheus-compatible export.

## The pitch

Track application metrics with counters (monotonically increasing), gauges (up/down), histograms (distribution).

```zig
const ziometrics = @import("ziometrics");

var reg: ziometrics.Registry(20) = .{};

// Counter: monotonically increasing
const reqs = reg.counter("http_requests").?;
reqs.inc();
reqs.add(10);
const total = reqs.get(); // 11

// Gauge: up/down values
const cpu = reg.gauge("cpu_percent").?;
cpu.set(72.5);
cpu.inc();  // 73.5
cpu.dec();  // 72.5

// Histogram: distribution
const latency = reg.histogram("request_latency_ms").?;
latency.observe(42.1);
latency.observe(8.3);
const mean = latency.mean(); // 25.2

// Export all metrics in Prometheus format
try reg.writePrometheus(writer);
```

## Install

```bash
zig fetch --save git+https://github.com/deblasis/ziometrics
```

Then in your `build.zig`:

```zig
const dep = b.dependency("ziometrics", .{
    .target = target,
    .optimize = optimize,
});
exe.root_module.addImport("ziometrics", dep.module("ziometrics"));
```

Requires Zig 0.16.

## API

- `Registry(max).counter(name)` / `.gauge(name)` / `.histogram(name)`
- `Counter.inc()` / `.add(n)` / `.get()` / `.reset()`
- `Gauge.set(v)` / `.inc()` / `.dec()` / `.get()`
- `Histogram.observe(value)` / `.mean()` / `.min` / `.max`
- `writePrometheus(writer)` — Prometheus text format

## Compatibility

- **Zig**: 0.16.0
- **Platforms**: Linux, macOS, Windows
- **Breaking changes**: follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html). Minor versions add features, patch versions fix bugs.

## License

MIT. Copyright (c) 2026 Alessandro De Blasis.
