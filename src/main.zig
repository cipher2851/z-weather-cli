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

    if (args.len >= 3) {
        lat = args[1];
        lon = args[2];
        location_name = "specified coordinates";
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

    std.debug.print("Response received:\n{s}\n", .{response_body.items});
    std.debug.print("\nNote: In a full implementation, a JSON parser would be used to extract temperature and windspeed.\n", .{});
}