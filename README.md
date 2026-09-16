# z-weather-cli

A simple weather CLI written in Zig.

## Prerequisites
- Zig compiler (0.11.0 or newer)

## Usage
```bash
# Fetch default weather (Berlin)
zig build run

# Fetch weather for specific coordinates (lat lon)
zig build run -- --lat 40.71 -74.00
```

Currently, the tool fetches real-time data from the Open-Meteo API to demonstrate HTTP capabilities and JSON parsing in Zig.