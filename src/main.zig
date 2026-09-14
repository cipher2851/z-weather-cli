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

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--lat") && i + 2 < args.len) {
            lat = args[i + 1];
            lon = args[i + 2];
            location_name = "specified coordinates";
            i += 2;
        } else if (i == 1 && args.len >= 3) {
            // Allow positional lat lon arguments
            lat = args[1];
            lon = args[2];
            location_name = "specified coordinates";
            i += 2;
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
    
    // Zero-allocation helper to extract value by key from simple JSON
    fn extractValue(body: []const u8, key: []const u8) []const u8 {
        var search_pos: usize = 0;
        while (search_pos < body.len) {
            if (std.mem.indexOfN(u8, body[search_pos..], key)) |idx| {
                const abs_idx = search_pos + idx;
                // Verify it's actually the key: "key":
                if (abs_idx > 0 and body[abs_idx - 1] == '"') {
                    const after_key = body[abs_idx + key.len ..];
                    if (after_key.len >= 1 and after_key[0] == '"') {
                        // This is a string key, check for colon
                        var colon_idx: usize = 0;
                        while (colon_idx < after_key.len) {
                            if (after_key[colon_idx] == ':') break;
                            colon_idx += 1;
                        }
                        if (colon_idx < after_key.len) {
                            var val_start = colon_idx + 1;
                            while (val_start < after_key.len and (after_key[val_start] == ' ' or after_key[val_start] == '\t')) {
                                val_start += 1;
                            }
                            var val_end = val_start;
                            while (val_end < after_key.len) {
                                const c = after_key[val_end];
                                if (c == ',' or c == '}' or c == ']' or c == '\n') break;
                                val_end += 1;
                            }
                            // Trim quotes if it's a string
                            var result = after_key[val_start..val_end];
                            if (result.len >= 2 and result[0] == '"' and result[result.len - 1] == '"') {
                                result = result[1..result.len - 1];
                            }
                            return result;
                        }
                    }
                }
            }
            search_pos += 1;
        }
        return "";
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