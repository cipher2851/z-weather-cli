\"const std = @import("std");

const OpenMeteoUrl = "https://api.open-meteo.com/v1/forecast?latitude=52.52&longitude=13.41&current_weather=true";

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("Fetching current weather for Berlin...\n", .{});

    var client = std.http.Client{ .allocator = allocator };
    var server_header_buffer: [1024]u8 = undefined;
    
    var request = try client.open(.GET, OpenMeteoUrl, .{});
    defer request.deinit();

    try request.send();
    try request.finish();

    var response_body = std.ArrayList(u8).init(allocator);
    defer response_body.deinit();

    while (try request.read()) |chunk| {
        try response_body.appendSlice(chunk);
    }

    std.debug.print("Response received:\n{s}\n", .{response_body.items});
    std.debug.print("\nNote: In a full implementation, a JSON parser would be used to extract temperature and windspeed.\n", .{});
}