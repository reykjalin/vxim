// This can contain internal events as well as Vaxis events.
// Internal events can be posted into the same queue as vaxis events to allow
// for a single event loop with exhaustive switching. Booya
const Event = union(enum) {
    key_press: vaxis.Key,
    winsize: vaxis.Winsize,
    mouse: vaxis.Mouse,
    mouse_focus: vaxis.Mouse,
};

const Widget = enum(u32) {
    FileMenuButton,
    AboutButton,
    AboutWindow,
    CloseAboutButton,
    ClickMe,
};

const Vxim = vxim.Vxim(Event, Widget);

const Menu = enum {
    File,
};

const Window = enum {
    About,
};

const State = struct {
    mouse: ?vaxis.Mouse = null,
    clicks: usize = 0,
    open_menu: ?Menu = null,
    open_window: ?Window = null,
};

var state: State = .{};

var debug_allocator: std.heap.DebugAllocator(.{}) = .init;

pub fn main() !void {
    const gpa, const is_debug = gpa: {
        break :gpa switch (builtin.mode) {
            .Debug, .ReleaseSafe => .{ debug_allocator.allocator(), true },
            .ReleaseFast, .ReleaseSmall => .{ std.heap.smp_allocator, false },
        };
    };
    defer if (is_debug) {
        _ = debug_allocator.deinit();
    };

    var vx: Vxim = .init(gpa);
    defer vx.deinit(gpa);

    try vx.startLoop(gpa, update);
}

pub fn update(ctx: Vxim.UpdateContext) anyerror!Vxim.UpdateResult {
    switch (ctx.current_event) {
        .key_press => |key| {
            if (key.matches('c', .{ .ctrl = true }))
                return .stop;
        },
        .mouse => |mouse| state.mouse = mouse,

        .winsize => {},
        .mouse_focus => |_| {},
    }

    ctx.root_win.clear();
    ctx.vx.setMouseShape(.default);

    // Main section of the app.
    {
        const modal_width = @min(40, ctx.root_win.width);
        const modal_height = @min(7, ctx.root_win.height);
        const modal = ctx.root_win.child(.{
            .width = modal_width,
            .height = modal_height,
            .x_off = ctx.root_win.width / 2 -| modal_width / 2,
            .y_off = ctx.root_win.height / 2 -| modal_height / 2,
            .border = .{ .where = .all },
        });
        const button_text = "Click Me!";

        const button_x: u16 =
            (modal_width / 2) -| ((@as(u16, @truncate(button_text.len)) + 2) / 2);
        const button_y: u16 = (modal_height / 2);

        const button_action =
            ctx.vxim.button(
                Widget.ClickMe,
                modal,
                .{ .x = button_x, .y = button_y, .text = button_text },
            );

        if (button_action == .clicked) state.clicks +|= 1;

        if (button_action == .hovered or button_action == .clicked) ctx.vx.setMouseShape(.pointer);

        const text = try std.fmt.allocPrint(ctx.arena, "Clicks: {d}", .{state.clicks});
        const text_x: u16 = (modal_width / 2) -| (@as(u16, @truncate(text.len)) / 2);
        const text_y: u16 = (modal_height / 2) -| 2;

        ctx.vxim.text(modal, .{ .text = text, .x = text_x, .y = text_y });
    }

    // About window
    if (state.open_window) |open_window| {
        if (open_window == .About) {
            const about_win = ctx.vxim.window(Widget.AboutWindow, ctx.root_win, .{
                .width = @min(ctx.root_win.width, 50),
                .height = @min(ctx.root_win.height, 20),
                .x = 10,
                .y = 10,
                .title = "About this program",
            });

            const close = ctx.vxim.button(
                Widget.CloseAboutButton,
                about_win,
                .{ .x = about_win.width / 2 -| 3, .y = about_win.height -| 1, .text = "Close" },
            );
            if (close == .clicked) {
                state.open_window = null;
            }

            if (close == .clicked or close == .hovered) ctx.vx.setMouseShape(.pointer);

            ctx.vxim.text(about_win, .{ .text = "VXIM v0.0.0", .y = 0 });
            ctx.vxim.text(
                about_win,
                .{ .text = "Experimental immediate mode renderer for libvaxis", .y = 3 },
            );
        }
    }

    // File Menu
    if (state.open_menu == .File) {
        const file_menu = ctx.root_win.child(.{
            .width = 7,
            .height = 1,
            .x_off = 0,
            .y_off = 1,
        });

        const about_button = ctx.vxim.button(
            Widget.AboutButton,
            file_menu,
            .{ .x = 0, .y = 0, .text = "About" },
        );

        if (about_button == .hovered or about_button == .clicked) ctx.vx.setMouseShape(.pointer);

        if (about_button == .clicked) {
            state.open_menu = null;
            state.open_window = .About;
        }

        if (file_menu.hasMouse(state.mouse) == null) {
            if (state.mouse.?.type == .press) state.open_menu = null;
        }
    }

    // Menu Bar
    {
        const menu_bar = ctx.root_win.child(.{
            .width = ctx.root_win.width,
            .height = 1,
            .x_off = 0,
            .y_off = 0,
        });

        const file_button = ctx.vxim.button(
            Widget.FileMenuButton,
            menu_bar,
            .{ .x = 0, .y = 0, .text = "File" },
        );

        if (file_button == .clicked) {
            state.open_menu = .File;
        }

        if (file_button == .hovered or file_button == .clicked) ctx.vx.setMouseShape(.pointer);
    }

    return .keep_going;
}

const std = @import("std");
const builtin = @import("builtin");

const vaxis = @import("vaxis");
const vxim = @import("vxim");
