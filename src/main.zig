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
        } else if (i + 2 < args.len) {
            // Handle positional args as lat/lon if they look like numbers
            lat = args[i];
            lon = args[i + 1];
            location_name = "specified coordinates";
            break;
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

    // Simple manual parsing of the JSON for current_weather
    const body = response_body.items;
    if (std.mem.indexOf(u8, body, "\"current_weather\":") != null) {
        const start_idx = std.mem.indexOf(u8, body, "\"temperature\":") orelse 0;
        const temp_start = std.mem.indexOf(u8, body[start_idx..], ",") orelse 0;
        // This is a very naive parser for demonstration purposes
        // In a production app, we would use a proper JSON library like zig-json
        std.debug.print("Weather data received successfully!\n", .{});
        std.debug.print("Raw Body: {s}\n", .{body});
        std.debug.print("Check the 'current_weather' object for temperature and windspeed.\n", .{});
    } else {
        std.debug.print("Failed to find weather data in response.\n", .{});
        std.debug.print("Response: {s}\n", .{body});
    }
}