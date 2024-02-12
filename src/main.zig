const std = @import("std");
const rl = @import("c.zig");
const Entry = std.fs.Dir.Entry;

const screen_width = 800;
const screen_height = 600;
const font_size = 30;

const DirEntry = struct {
    name: [:0]const u8,
    open: bool,
};

const FileEntry = [:0]const u8;

const EntryList = struct {
    allocator: std.mem.Allocator,
    dirs: std.ArrayListUnmanaged(DirEntry),
    files: std.ArrayListUnmanaged(FileEntry),

    fn init(allocator: std.mem.Allocator) EntryList {
        return .{
            .allocator = allocator,
            .dirs = std.ArrayListUnmanaged(DirEntry){},
            .files = std.ArrayListUnmanaged(FileEntry){},
        };
    }

    fn appendDir(self: *EntryList, name: [:0]const u8) !void {
        try self.dirs.append(self.allocator, .{ .name = name, .open = false });
    }

    fn appendFile(self: *EntryList, name: [:0]const u8) !void {
        try self.files.append(self.allocator, name);
    }

    fn deinit(self: *EntryList) void {
        self.dirs.deinit(self.allocator);
        self.files.deinit(self.allocator);
    }

    fn getDirs(self: EntryList) []DirEntry {
        return self.dirs.items;
    }

    fn getFiles(self: EntryList) []FileEntry {
        return self.files.items;
    }
};

var arena: std.mem.Allocator = undefined;

pub fn main() !void {
    rl.InitWindow(screen_width, screen_height, "raylib window");
    rl.SetTargetFPS(60);

    var arena_inst = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_inst.deinit();
    arena = arena_inst.allocator();

    var list = EntryList.init(arena);

    {
        var dir = try std.fs.cwd().openDir(".", .{ .iterate = true });
        var iter = dir.iterate();
        while (try iter.next()) |entry| {
            const name = try arena.dupeZ(u8, entry.name);
            switch (entry.kind) {
                .directory => try list.appendDir(name),
                .file => try list.appendFile(name),
                else => |tag| std.log.info("encountered filetype '{s}'", .{@tagName(tag)}),
            }
        }
    }

    while (!rl.WindowShouldClose()) {
        const m_pos = rl.GetMousePosition();
        var start_pos = vec2(i32, 50, 50);

        rl.BeginDrawing();

        rl.ClearBackground(rl.RAYWHITE);

        rl.DrawFPS(0, 0);

        for (list.getDirs()) |*dir| {
            const arrow_pos = vec2(f32, start_pos.x - font_size, start_pos.y);

            const button = drawArrowV(arrow_pos, font_size - 5, dir.open);
            if (rl.IsMouseButtonPressed(rl.MOUSE_BUTTON_LEFT) and
                rl.CheckCollisionPointRec(m_pos, button))
            {
                dir.open = !dir.open;
            }

            rl.DrawText(
                dir.name.ptr,
                @intFromFloat(start_pos.x),
                @intFromFloat(start_pos.y),
                font_size,
                rl.DARKBLUE,
            );
            start_pos.y += font_size;
        }

        for (list.getFiles()) |file| {
            rl.DrawText(
                file.ptr,
                @intFromFloat(start_pos.x),
                @intFromFloat(start_pos.y),
                font_size,
                rl.LIGHTGRAY,
            );
            start_pos.y += font_size;
        }

        rl.EndDrawing();
    }

    rl.CloseWindow();
}

inline fn vec2(comptime T: type, x: T, y: T) rl.Vector2 {
    return .{
        .x = x,
        .y = y,
    };
}

inline fn rect(x: i32, y: i32, w: i32, h: i32) rl.Rectangle {
    return .{
        .x = x,
        .y = y,
        .width = w,
        .height = h,
    };
}

inline fn drawArrow(x: f32, y: f32, size: f32, down: bool) rl.Rectangle {
    const offset = size * 0.2;
    const r = rl.Rectangle{
        .x = x,
        .y = y,
        .width = size,
        .height = size,
    };
    rl.DrawRectangleRec(r, rl.BLACK);
    if (!down)
        rl.DrawTriangle(
            vec2(f32, x + offset, y + offset),
            vec2(f32, x + offset, y + size - offset),
            vec2(f32, x + size - offset, y + size / 2.0),
            rl.LIGHTGRAY,
        )
    else
        rl.DrawTriangle(
            vec2(f32, x + size - offset, y + offset),
            vec2(f32, x + offset, y + offset),
            vec2(f32, x + size / 2.0, y + size - offset),
            rl.LIGHTGRAY,
        );

    return r;
}

inline fn drawArrowV(vec: rl.Vector2, size: i32, down: bool) rl.Rectangle {
    return drawArrow(vec.x, vec.y, size, down);
}
