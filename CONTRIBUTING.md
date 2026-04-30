# Contributing to ziometrics

Thanks for your interest in contributing!

## Development Setup

1. Install [Zig 0.16.0](https://ziglang.org/download/)
2. Clone this repository
3. Run `zig build test` to verify everything works

## Pull Request Process

1. Fork the repository
2. Create a feature branch
3. Add tests for any new functionality
4. Ensure all tests pass: `zig build test`
5. Run the formatter: `zig fmt .`
6. Submit a pull request

## Code Style

- Follow [Zig's style guide](https://ziglang.org/documentation/master/#Style-Guide)
- Run `zig fmt` before committing
- Add doc comments to all public symbols
- Keep functions focused and small

## Reporting Issues

- Use GitHub Issues
- Include Zig version (`zig version`)
- Include minimal reproduction steps

## AI Usage Policy

We welcome contributions made with AI assistance, but:
- You must understand and stand behind every line of code you submit
- Generated code must meet the same quality standards as hand-written code
- All code must be properly tested and documented
