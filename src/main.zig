const std = @import("std");
const rl = @import("c.zig");
const Entry = std.fs.Dir.Entry;
const ArenaAllocator = std.heap.ArenaAllocator;
const Allocator = std.mem.Allocator;

const screen_width = 800;
const screen_height = 600;
const font_size = 30;

const DirEntry = struct {
    name: [:0]const u8,
    open: bool,
};

const FileEntry = [:0]const u8;

const EntryList = struct {
    arena: ArenaAllocator,
    dirs: std.ArrayListUnmanaged(DirEntry),
    files: std.ArrayListUnmanaged(FileEntry),
    children: std.StringHashMapUnmanaged(EntryList),

    fn init(allocator: Allocator) EntryList {
        return .{
            .arena = ArenaAllocator.init(allocator),
            .dirs = std.ArrayListUnmanaged(DirEntry){},
            .files = std.ArrayListUnmanaged(FileEntry){},
            .children = std.StringHashMapUnmanaged(EntryList){},
        };
    }

    fn appendDir(self: *EntryList, name: [:0]const u8) !void {
        try self.dirs.append(self.arena.allocator(), .{ .name = name, .open = false });
    }

    fn appendFile(self: *EntryList, name: [:0]const u8) !void {
        try self.files.append(self.arena.allocator(), name);
    }

    fn deinit(self: *EntryList) void {
        self.arena.deinit();
    }

    fn getDirs(self: EntryList) []DirEntry {
        return self.dirs.items;
    }

    fn getFiles(self: EntryList) []FileEntry {
        return self.files.items;
    }
};

fn printList(list: *EntryList, x: f32, y: f32, mouse_pos: rl.Vector2) !f32 {
    const arena = list.arena.allocator();
    var yi = y;
    for (list.getDirs()) |*dir| {
        const arrow_pos = vec2(f32, x, yi);

        const button = drawArrowV(arrow_pos, font_size - 5, dir.open);

        rl.DrawText(
            dir.name.ptr,
            @intFromFloat(x + font_size),
            @intFromFloat(yi),
            font_size,
            rl.DARKBLUE,
        );

        if (dir.open) {
            const res = try list.children.getOrPut(arena, dir.name);
            if (res.found_existing) {
                const new_y = try printList(res.value_ptr, x + font_size, yi + font_size + 5, mouse_pos);
                yi = new_y;
            } else {
                const path = try std.fs.path.join(arena, &.{ ".", dir.name });
                res.value_ptr.* = try iterateDir(arena, path);
            }
        }

        if (rl.IsMouseButtonPressed(rl.MOUSE_BUTTON_LEFT) and
            rl.CheckCollisionPointRec(mouse_pos, button))
        {
            dir.open = !dir.open;
            if (!dir.open) {
                const match = list.children.getPtr(dir.name) orelse unreachable;
                match.deinit();
            }
        }
        yi += font_size;
    }

    for (list.getFiles()) |file| {
        rl.DrawText(
            file.ptr,
            @intFromFloat(x),
            @intFromFloat(yi),
            font_size,
            rl.LIGHTGRAY,
        );
        yi += font_size;
    }

    return yi - font_size / 2;
}

fn iterateDir(arena: Allocator, path: []const u8) !EntryList {
    var list = EntryList.init(arena);
    var dir = try std.fs.cwd().openDir(path, .{ .iterate = true });
    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        const name = try arena.dupeZ(u8, entry.name);
        switch (entry.kind) {
            .directory => try list.appendDir(name),
            .file => try list.appendFile(name),
            else => |tag| std.log.info("encountered filetype '{s}'", .{@tagName(tag)}),
        }
    }

    return list;
}

pub fn main() !void {
    rl.InitWindow(screen_width, screen_height, "filetree");
    rl.SetTargetFPS(60);

    var gpa_inst = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa_inst.deinit();
    const gpa = gpa_inst.allocator();

    var list = EntryList.init(gpa);
    defer list.deinit();
    {
        var dir = try std.fs.cwd().openDir(".", .{ .iterate = true });
        var iter = dir.iterate();
        while (try iter.next()) |entry| {
            const name = try list.arena.allocator().dupeZ(u8, entry.name);
            switch (entry.kind) {
                .directory => try list.appendDir(name),
                .file => try list.appendFile(name),
                else => |tag| std.log.info("encountered filetype '{s}'", .{@tagName(tag)}),
            }
        }
    }

    var anchor = vec2(f32, 50, 50);
    while (!rl.WindowShouldClose()) {
        const m_pos = rl.GetMousePosition();
        const start_x: f32 = anchor.x;
        const start_y: f32 = anchor.y;

        if (rl.IsKeyDown(rl.KEY_Q)) break;
        if (rl.IsKeyDown(rl.KEY_UP)) anchor.y += 10;
        if (rl.IsKeyDown(rl.KEY_DOWN)) anchor.y -= 10;
        if (rl.IsKeyDown(rl.KEY_LEFT)) anchor.x += 10;
        if (rl.IsKeyDown(rl.KEY_RIGHT)) anchor.x -= 10;

        rl.BeginDrawing();

        rl.ClearBackground(rl.RAYWHITE);
        _ = try printList(&list, start_x, start_y, m_pos);

        rl.DrawFPS(0, 0);

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
