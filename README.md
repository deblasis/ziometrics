# ziometrics

Metrics collection for Zig

Metrics collection library for Zig. Counters, gauges, and histograms. Prometheus-compatible exposition format.

## Features

- counters, gauges, histograms
- Prometheus exposition format
- label support
- registry-based API

## Quick Start

```zig
const ziometrics = @import("ziometrics");

pub fn main() !void {
    // See examples/ for runnable code
}
```

## Installation

Add to your `build.zig.zon`:

```zig
.{
    .dependencies = .{
        .ziometrics = .{ .url = "https://github.com/deblasis/ziometrics/archive/refs/heads/main.tar.gz", .hash = "..." },
    },
}
```

Then in your `build.zig`:

```zig
const ziometrics = b.dependency("ziometrics", .{
    .target = target,
    .optimize = optimize,
});
exe.root_module.addImport("ziometrics", ziometrics.module("ziometrics"));
```

## Examples

Run the included example:

```bash
zig build run-example
```

## API Reference

See [src/ziometrics.zig](src/ziometrics.zig) for full documentation. All public symbols have doc comments.

## Compatibility

- **Zig:** 0.16.0
- **Platforms:** Linux, macOS, Windows
- **Breaking changes:** Follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html). Minor versions may add features, patch versions fix bugs.

## License

MIT
