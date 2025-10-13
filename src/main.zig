// This can contain internal events as well as Vaxis events.
// Internal events can be posted into the same queue as vaxis events to allow
// for a single event loop with exhaustive switching. Booya
const Event = union(enum) {
    key_press: vaxis.Key,
    winsize: vaxis.Winsize,
    mouse: vaxis.Mouse,
};

const State = struct {
    mouse: ?vaxis.Mouse = null,
    clicks: usize = 0,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const deinit_status = gpa.deinit();
        //fail test; can't try in defer as defer is executed after we return
        if (deinit_status == .leak) {
            std.log.err("memory leak", .{});
        }
    }
    const alloc = gpa.allocator();

    var arena_state: std.heap.ArenaAllocator = .init(alloc);
    defer arena_state.deinit();

    const arena = arena_state.allocator();

    // Initialize a tty
    var buffer: [1024]u8 = undefined;
    var tty = try vaxis.Tty.init(&buffer);
    defer tty.deinit();

    // Initialize Vaxis
    var vx = try vaxis.init(alloc, .{});
    // deinit takes an optional allocator. If your program is exiting, you can
    // choose to pass a null allocator to save some exit time.
    defer vx.deinit(alloc, tty.writer());

    // The event loop requires an intrusive init. We create an instance with
    // stable pointers to Vaxis and our TTY, then init the instance. Doing so
    // installs a signal handler for SIGWINCH on posix TTYs
    //
    // This event loop is thread safe. It reads the tty in a separate thread
    var loop: vaxis.Loop(Event) = .{
        .tty = &tty,
        .vaxis = &vx,
    };
    try loop.init();

    // Start the read loop. This puts the terminal in raw mode and begins
    // reading user input
    try loop.start();
    defer loop.stop();

    // Optionally enter the alternate screen
    try vx.enterAltScreen(tty.writer());

    // Sends queries to terminal to detect certain features. This should always
    // be called after entering the alt screen, if you are using the alt screen
    try vx.queryTerminal(tty.writer(), 1 * std.time.ns_per_s);

    // enable mouse events.
    try vx.setMouseMode(tty.writer(), true);

    var state: State = .{};

    while (true) {
        // nextEvent blocks until an event is in the queue
        const event = loop.nextEvent();
        // exhaustive switching ftw. Vaxis will send events if your Event enum
        // has the fields for those events (ie "key_press", "winsize")
        switch (event) {
            .key_press => |key| {
                if (key.matches('c', .{ .ctrl = true }))
                    break;
            },

            // winsize events are sent to the application to ensure that all
            // resizes occur in the main thread. This lets us avoid expensive
            // locks on the screen. All applications must handle this event
            // unless they aren't using a screen (IE only detecting features)
            //
            // The allocations are because we keep a copy of each cell to
            // optimize renders. When resize is called, we allocated two slices:
            // one for the screen, and one for our buffered screen. Each cell in
            // the buffered screen contains an ArrayList(u8) to be able to store
            // the grapheme for that cell. Each cell is initialized with a size
            // of 1, which is sufficient for all of ASCII. Anything requiring
            // more than one byte will incur an allocation on the first render
            // after it is drawn. Thereafter, it will not allocate unless the
            // screen is resized
            .winsize => |ws| try vx.resize(alloc, tty.writer(), ws),
            .mouse => |mouse| state.mouse = mouse,
        }

        // vx.window() returns the root window. This window is the size of the
        // terminal and can spawn child windows as logical areas. Child windows
        // cannot draw outside of their bounds
        const win = vx.window();

        // Clear the entire space because we are drawing in immediate mode.
        // vaxis double buffers the screen. This new frame will be compared to
        // the old and only updated cells will be drawn
        win.clear();

        const button_text = "Click Me!";

        const button_x: u16 = (win.width / 2) -| ((@as(u16, @truncate(button_text.len)) + 2) / 2);
        const button_y: u16 = (win.height / 2) +| 1;

        if (vxim.button(win, .{ .x = button_x, .y = button_y, .text = button_text, .mouse = state.mouse }) == .pressed) {
            state.clicks +|= 1;
        }

        const text = try std.fmt.allocPrint(arena, "Clicks: {d}", .{state.clicks});
        const text_x: u16 = (win.width / 2) -| (@as(u16, @truncate(text.len)) / 2);
        const text_y: u16 = (win.height / 2) -| 1;

        vxim.text(win, .{ .text = text, .x = text_x, .y = text_y });

        // Render the screen. Using a buffered writer will offer much better
        // performance, but is not required
        try vx.render(tty.writer());

        _ = arena_state.reset(.retain_capacity);
    }
}

const std = @import("std");

const vaxis = @import("vaxis");
const vxim = @import("vxim");
