const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var lat: []const u8 = "52.52";
    var lon: []const u8 = "13.41";
    var location_name: []const u8 = "Berlin";

    // Basic argument parsing
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--lat") && i + 2 < args.len) {
            lat = args[i + 1];
            lon = args[i + 2];
            location_name = "specified coordinates";
            break;
        } else if (i >= 1 && i + 1 < args.len) {
            // Handle positional args as lat/lon (skipping executable path)
            if (i == 1) {
                lat = args[1];
                lon = args[2];
                location_name = "specified coordinates";
                break;
            }
        }
    }

    const url = try std.fmt.allocPrint(allocator, "https://api.open-meteo.com/v1/forecast?latitude={s}&longitude={s}&current_weather=true", .{ lat, lon });
    defer allocator.free(url);

    std.debug.print("Fetching current weather for {s} ({s}, {s})...\n", .{ location_name, lat, lon });

    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();

    var server_header_buffer: [1024]u8 = undefined;
    
    var request = try client.open(.GET, url, .{ .response_headers_buffer = &server_header_buffer });
    defer request.deinit();

    try request.send();
    try request.wait();

    var response_body = std.ArrayList(u8).init(allocator);
    defer response_body.deinit();

    while (try request.read()) |chunk| {
        try response_body.appendSlice(chunk);
    }

    const body = response_body.items;
    
    // Helper to extract value by key from simple JSON
    fn extractValue(body: []const u8, key: []const u8) []const u8 {
        const key_pattern = try std.fmt.allocPrint(std.heap.page_allocator, "\"{s}\":", .{key});
        defer std.heap.page_allocator.free(key_pattern);
        
        const start_idx = std.mem.indexOf(u8, body, key_pattern) orelse return "";
        const value_start = start_idx + key_pattern.len;
        
        var end_idx: usize = value_start;
        while (end_idx < body.len) {
            const char = body[end_idx];
            if (char == ',' or char == '}' or char == ' ') {
                break;
            }
            end_idx += 1;
        }
        return body[value_start..end_idx];
    }

    if (std.mem.indexOf(u8, body, "\"current_weather\":") != null) {
        const temp = extractValue(body, "temperature");
        const wind = extractValue(body, "windspeed");
        
        std.debug.print("\n--- Weather Report ---\n", .{});
        std.debug.print("Location: {s}\n", .{location_name});
        std.debug.print("Temperature: {s}°C\n", .{temp});
        std.debug.print("Windspeed: {s} km/h\n", .{wind});
        std.debug.print("---------------------\n", .{});
    } else {
        std.debug.print("Failed to find weather data in response.\n", .{});
        std.debug.print("Response: {s}\n", .{body});
    }
}