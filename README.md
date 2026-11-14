# z-weather-cli

A simple weather CLI written in Zig.

## Prerequisites
- Zig compiler (0.12.0)

## Usage
```bash
# Fetch default weather (Berlin)
zig build run

# Fetch weather for a city
zig build run -- --city Tokyo

# Fetch weather for specific coordinates (lat lon)
zig build run -- --lat 40.71 -74.00

# Use Fahrenheit and JSON output
zig build run -- --city Tokyo --unit F --json
```

Options:
- `--city <name>`: Fetch weather for a city name
- `--lat <lat> <lon>`: Specify latitude and longitude
- `--unit <C|F>`: Temperature unit (Celsius or Fahrenheit)
- `--json`: Output in JSON format
- `--verbose`: Print raw API responses
- `--silent`: Suppress status messages
- `--version`: Print version and exit
- `--help, -h`: Show help

Currently, the tool fetches real-time data from the Open-Meteo API to demonstrate HTTP capabilities and JSON parsing in Zig. It provides information on temperature, wind speed, and current weather conditions.

## Development
```bash
# Build the executable
zig build

# Check that the project compiles (without running)
zig build check

# Run the test suite
zig build test

# Format source files
zig build fmt

# Check formatting without modifying files
zig build fmt-check

# Run compilation checks, tests, and formatting checks
zig build ci
```
