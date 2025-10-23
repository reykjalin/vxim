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
    FileMenu,
    AboutButton,
    AboutWindow,
    QuitButton,
    CloseAboutButton,
    ClickMe,
    CounterModal,
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

    // Main section of the app.
    {
        const modal_width = @min(40, ctx.root_win.width);
        const modal_height = @min(7, ctx.root_win.height);
        const modal = ctx.vxim.window(.CounterModal, ctx.root_win, .{
            .width = modal_width,
            .height = modal_height,
            .x = ctx.root_win.width / 2 -| modal_width / 2,
            .y = ctx.root_win.height / 2 -| modal_height / 2,
        });
        const button_text = "Click Me!";

        const button_x: u16 =
            (modal_width / 2) -| ((@as(u16, @truncate(button_text.len)) + 2) / 2);
        const button_y: u16 = (modal_height / 2);

        const button_action =
            ctx.vxim.button(
                .ClickMe,
                modal,
                .{ .x = button_x, .y = button_y, .text = button_text },
            );

        if (button_action == .clicked) state.clicks +|= 1;

        const text = try std.fmt.allocPrint(ctx.vxim.arena(), "Clicks: {d}", .{state.clicks});
        const text_x: u16 = (modal_width / 2) -| (@as(u16, @truncate(text.len)) / 2);
        const text_y: u16 = (modal_height / 2) -| 2;

        ctx.vxim.text(modal, .{ .text = text, .x = text_x, .y = text_y, .allow_selection = true });
    }

    // About window
    if (state.open_window) |open_window| {
        if (open_window == .About) {
            const about_win = ctx.vxim.window(.AboutWindow, ctx.root_win, .{
                .width = @min(ctx.root_win.width, 50),
                .height = @min(ctx.root_win.height, 20),
                .x = 10,
                .y = 10,
                .title = "About this program",
            });

            const about_body = ctx.vxim.padding(about_win, .{ .all = 1 });

            const close = ctx.vxim.button(
                .CloseAboutButton,
                about_body,
                .{ .x = about_body.width / 2 -| 3, .y = about_body.height -| 1, .text = "Close" },
            );
            if (close == .clicked) {
                state.open_window = null;
            }

            ctx.vxim.text(
                about_body,
                .{ .text = "VXIM v0.0.0", .allow_selection = true },
            );
            ctx.vxim.text(
                about_body,
                .{
                    .text = "Experimental immediate mode renderer for libvaxis",
                    .y = 3,
                    .allow_selection = true,
                },
            );
        }
    }

    const menuAction = ctx.vxim.menuBar(ctx.root_win, &.{
        .{
            .name = "File",
            .id = .FileMenu,
            .items = &.{
                .{ .name = "About", .id = .AboutButton },
                .{ .name = "Quit", .id = .QuitButton },
            },
        },
    });

    if (menuAction) |action| {
        if (action.id == .AboutButton and action.action == .clicked) state.open_window = .About;
        if (action.id == .QuitButton and action.action == .clicked) return .stop;
    }

    return .keep_going;
}

const std = @import("std");
const builtin = @import("builtin");

const vaxis = @import("vaxis");
const vxim = @import("vxim");
