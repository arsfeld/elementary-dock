/*
 * SPDX-License-Identifier: GPL-3.0
 * SPDX-FileCopyrightText: 2025 elementary, Inc. (https://elementary.io)
 */

public class Dock.DynamicWorkspaceIcon : ContainerItem, WorkspaceItem {
    public int workspace_index { get { return (int) WorkspaceSystem.get_default ().workspaces.get_n_items (); } }

    private Gtk.Image image;
    private IconResolution resolution;

    public DynamicWorkspaceIcon () {
        Object (group: Group.NONE);
    }

    construct {
        var keybinding_settings = new GLib.Settings ("io.elementary.desktop.wm.keybindings");

        image = new Gtk.Image () {
            hexpand = true,
            vexpand = true
        };
        resolution = IconResolution.attach (image, new ThemedIcon ("list-add-symbolic"));
        bind_property ("render-scale", resolution, "render-scale", SYNC_CREATE);
        image.add_css_class ("add-image");

        child = image;
        tooltip_text = Granite.markup_accel_tooltip (
            keybinding_settings.get_strv ("switch-to-workspace-last"),
            _("New Workspace")
        );

        WorkspaceSystem.get_default ().workspaces.items_changed.connect (update_active_state);
        WindowSystem.get_default ().notify["active-workspace"].connect (update_active_state);

        dock_settings.bind_with_mapping (
            "icon-size", image, "pixel_size", DEFAULT | GET,
            (value, variant, user_data) => {
                var icon_size = variant.get_int32 ();
                value.set_int (icon_size / 2);
                return true;
            },
            (value, expected_type, user_data) => {
                return new Variant.maybe (null, null);
            },
            null, null
        );

        gesture_click.button = Gdk.BUTTON_PRIMARY;
        gesture_click.released.connect (switch_to_new_workspace);
    }

    private void update_active_state () {
        unowned var workspace_system = WorkspaceSystem.get_default ();
        unowned var window_system = WindowSystem.get_default ();
        state = (workspace_system.workspaces.get_n_items () == window_system.active_workspace) ? State.ACTIVE : State.HIDDEN;
    }

    private async void switch_to_new_workspace () {
        var n_workspaces = (int) WorkspaceSystem.get_default ().workspaces.get_n_items ();
        var index = WindowSystem.get_default ().active_workspace;

        if (index == n_workspaces) {
            GalaDBus.open_multitasking_view ();
            return;
        }

        try {
            yield WindowSystem.get_default ().desktop_integration.activate_workspace (n_workspaces);
        } catch (Error e) {
            warning ("Couldn't switch to new workspace: %s", e.message);
        }
    }

    public void window_entered (Window window) {
        resolution.icon = window.icon;
        set_state_flags (DROP_ACTIVE, false);
    }

    public void window_left () {
        resolution.icon = new ThemedIcon ("list-add-symbolic");
        unset_state_flags (DROP_ACTIVE);
    }
}
