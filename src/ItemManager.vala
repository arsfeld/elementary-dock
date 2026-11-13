/*
 * SPDX-License-Identifier: GPL-3.0
 * SPDX-FileCopyrightText: 2023-2025 elementary, Inc. (https://elementary.io)
 */

 public class Dock.ItemManager : Gtk.Box {
    private static Settings settings;

    private static GLib.Once<ItemManager> instance;
    public static unowned ItemManager get_default () {
        return instance.once (() => { return new ItemManager (); });
    }

    public Launcher? added_launcher { get; set; default = null; }

    public ZoomController zoom { get; private set; }

    private Gtk.EventControllerMotion motion;
    private Gtk.DropControllerMotion drop_motion;
    private Gtk.Popover? frozen_popover = null;
    private uint zoom_tick_id = 0;

    private DynamicWorkspaceIcon dynamic_workspace_item;
    private StackStore stack_store;

#if WORKSPACE_SWITCHER
    private Gtk.Separator separator;
#endif

    static construct {
        settings = new Settings ("io.elementary.dock");
    }

    construct {
        zoom = new ZoomController (this);
        zoom.changed.connect (queue_zoom);

        var app_group = new ItemGroup (AppSystem.get_default ().apps, (obj) => new Launcher ((App) obj));

        var background_item = new BackgroundItem ();
        var background_group = new ItemGroup (background_item.group_model, (obj) => (BackgroundItem) obj);
        stack_store = new StackStore ();
        var stack_group = new ItemGroup (stack_store.configs, (obj) => new StackItem ((StackConfig) obj));

#if WORKSPACE_SWITCHER
        dynamic_workspace_item = new DynamicWorkspaceIcon ();

        separator = new Gtk.Separator (VERTICAL) {
            valign = START,
            margin_top = Launcher.PADDING,
        };
        settings.bind ("icon-size", separator, "height-request", GET);
#endif

        append (app_group);
        append (stack_group);
        append (background_group);
#if WORKSPACE_SWITCHER
        append (separator);
        append (new ItemGroup (WorkspaceSystem.get_default ().workspaces, (obj) => new WorkspaceIconGroup ((Workspace) obj)));
        // A one-item group so the new-workspace button zooms and shifts like every other item.
        var dynamic_store = new ListStore (typeof (DynamicWorkspaceIcon));
        dynamic_store.append (dynamic_workspace_item);
        append (new ItemGroup (dynamic_store, (obj) => (DynamicWorkspaceIcon) obj));
#endif
        overflow = VISIBLE;

        // Items arriving or leaving, and the widths animating with them, move the
        // magnified spot under a pointer that has not.
        for (var child = get_first_child (); child != null; child = child.get_next_sibling ()) {
            if (child is ItemGroup) {
                child.notify["rest-width"].connect (queue_zoom);
                ((ItemGroup) child).children_changed.connect (queue_zoom);
            }
        }

        motion = new Gtk.EventControllerMotion ();
        motion.enter.connect ((x, y) => update_pointer (x));
        motion.motion.connect ((x, y) => update_pointer (x));
        motion.leave.connect (on_pointer_left);
        add_controller (motion);

        // Any drag over the dock (reordering, or a file coming in) puts it at rest,
        // so drag-and-drop keeps working against fixed slot sizes.
        drop_motion = new Gtk.DropControllerMotion ();
        drop_motion.enter.connect (() => zoom.pointer_left ());
        add_controller (drop_motion);

        maybe_zoom_for_test ();

        var drop_target_file = new Gtk.DropTarget (typeof (File), COPY) {
            preload = true
        };
        add_controller (drop_target_file);

        double drop_x, drop_y;
        drop_target_file.enter.connect ((x, y) => {
            drop_x = x;
            drop_y = y;
            return COPY;
        });

        drop_target_file.notify["value"].connect (() => {
            if (drop_target_file.get_value () == null) {
                return;
            }

            if (drop_target_file.get_value ().get_object () == null) {
                return;
            }

            if (!(drop_target_file.get_value ().get_object () is File)) {
                return;
            }

            var file = (File) drop_target_file.get_value ().get_object ();
            var app_info = new DesktopAppInfo.from_filename (file.get_path ());

            if (app_info == null) {
                return;
            }

            var app_system = AppSystem.get_default ();

            var app = app_system.get_app (app_info.get_id ());
            if (app != null) {
                app.pinned = true;
                drop_target_file.reject ();
                return;
            }

            app = app_system.add_app_for_id (app_info.get_id ());

            for (var child = app_group.get_first_child (); child != null; child = child.get_next_sibling ()) {
                if (child is Launcher && child.app == app) {
                    added_launcher = (Launcher) child;
                    added_launcher.moving = true;
                    break;
                }
            }
        });

        BaseItem? current_base_item = null;
        drop_target_file.motion.connect ((x, y) => {
            if (added_launcher == null) {
                current_base_item = null;
                return COPY;
            }

            var base_item = (BaseItem) pick (x, y, DEFAULT).get_ancestor (typeof (BaseItem));
            if (base_item == current_base_item) {
                return COPY;
            }

            current_base_item = base_item;

            if (base_item != null) {
                Graphene.Point translated;
                compute_point (base_item, { (float) x, (float) y}, out translated);
                base_item.calculate_dnd_move (added_launcher, translated.x, translated.y);
            }

            return COPY;
        });

        drop_target_file.leave.connect (() => {
            current_base_item = null;

            if (added_launcher != null) {
                //Without idle it crashes when the cursor is above the launcher
                Idle.add (() => {
                    added_launcher.app.pinned = false;
                    added_launcher = null;
                    return Source.REMOVE;
                });
            }
        });

        drop_target_file.drop.connect (() => {
            if (added_launcher != null) {
                added_launcher.moving = false;
                added_launcher = null;
                return true;
            }
            return false;
        });

        map.connect (() => {
            AppSystem.get_default ().load.begin ();
            background_item.load ();
#if WORKSPACE_SWITCHER
            WorkspaceSystem.get_default ().load.begin ();
#endif
        });
    }

    public void move_launcher_after (BaseItem source, int target_index) {
        if (source is Launcher) {
            AppSystem.get_default ().reorder_app (source.app, target_index);
        } else if (source is WorkspaceIconGroup) {
            WorkspaceSystem.get_default ().reorder_workspace (source.workspace, target_index);
        } else {
            warning ("Tried to move neither launcher nor icon group");
        }
    }

    public void launch (uint index) {
        if (index < 1 || index > AppSystem.get_default ().apps.get_n_items ()) {
            return;
        }

        var context = Gdk.Display.get_default ().get_app_launch_context ();
        var app = (App) AppSystem.get_default ().apps.get_item (index - 1);
        app.launch (context);
    }

    // Test hook for screenshot checks: with DOCK_ZOOM_AT=<slots>, the dock zooms
    // 1 s after it starts as if the pointer rested that many launcher widths from
    // its left edge, and stays zoomed until a real pointer enters and leaves it.
    // It fires before DOCK_STACKS_OPEN (1.5 s), so a stack popover opens on the
    // zoomed layout.
    private void maybe_zoom_for_test () {
        var wanted = Environment.get_variable ("DOCK_ZOOM_AT");
        if (wanted == null) {
            return;
        }

        var slots = double.parse (wanted);
        Timeout.add_once (1000, () => {
            message ("DOCK_ZOOM_AT: zooming at %g slots", slots);
            zoom.pointer_moved (slots * get_launcher_size ());
        });
    }

    private void update_pointer (double x) {
        if (drop_motion.contains_pointer || find_open_popover () != null) {
            return;
        }

        zoom.pointer_moved (ZoomMath.rest_x (x, get_width (), get_rest_width ()));
    }

    private void on_pointer_left () {
        var popover = find_open_popover ();
        if (popover == null) {
            zoom.pointer_left ();
            return;
        }

        // Hold the zoom while the popover is open, so its anchor does not slide away from it.
        if (popover != frozen_popover) {
            if (frozen_popover != null) {
                frozen_popover.closed.disconnect (on_frozen_popover_closed);
            }

            frozen_popover = popover;
            popover.closed.connect (on_frozen_popover_closed);
        }
    }

    private void on_frozen_popover_closed () {
        frozen_popover.closed.disconnect (on_frozen_popover_closed);
        frozen_popover = null;
        if (!motion.contains_pointer) {
            zoom.pointer_left ();
        }
    }

    private Gtk.Popover? find_open_popover () {
        for (var group = get_first_child (); group != null; group = group.get_next_sibling ()) {
            if (!(group is ItemGroup)) {
                continue;
            }

            for (var item = group.get_first_child (); item != null; item = item.get_next_sibling ()) {
                var popover = ((BaseItem) item).get_open_popover ();
                if (popover != null) {
                    return popover;
                }
            }
        }

        return null;
    }

    private static double get_child_rest_width (Gtk.Widget child) {
        if (child is ItemGroup) {
            return ((ItemGroup) child).rest_width;
        }

        if (!child.visible) {
            return 0.0;
        }

        // Includes margins, so the separator's spacing counts.
        int minimum, natural, minimum_baseline, natural_baseline;
        child.measure (HORIZONTAL, -1, out minimum, out natural, out minimum_baseline, out natural_baseline);
        return natural;
    }

    private double get_rest_width () {
        var width = 0.0;
        for (var child = get_first_child (); child != null; child = child.get_next_sibling ()) {
            width += get_child_rest_width (child);
        }

        return width;
    }

    private void queue_zoom () {
        if (zoom_tick_id != 0) {
            return;
        }

        zoom_tick_id = add_tick_callback (() => {
            zoom_tick_id = 0;
            apply_zoom ();
            return Source.REMOVE;
        });
    }

    private void apply_zoom () {
        var offset = 0.0;
        for (var child = get_first_child (); child != null; child = child.get_next_sibling ()) {
            if (child is ItemGroup) {
                ((ItemGroup) child).apply_zoom (zoom, offset);
            }

            offset += get_child_rest_width (child);
        }

        (get_root () as MainWindow)?.update_input_region ();
    }

    public static int get_launcher_size () {
        return settings.get_int ("icon-size") + Launcher.PADDING * 2;
    }
}
