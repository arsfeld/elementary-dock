/*
 * SPDX-License-Identifier: GPL-3.0
 *
 * The io.elementary.dock `stacks` key as a list model of StackConfig.
 */

public class Dock.StackStore : Object {
    public ListModel configs { get { return store; } }

    private Settings settings;
    private ListStore store;
    // What `store` holds, as a list StackList can diff against.
    private GenericArray<StackConfig> current = new GenericArray<StackConfig> ();

    construct {
        // The feeds the stacks' progress comes from; started here, never in unit tests.
        LauncherProgress.get_default ().start ();
        AppCenterJobs.get_default ().start ();
        store = new ListStore (typeof (StackConfig));
        settings = new Settings ("io.elementary.dock");
        if (settings.settings_schema.has_key ("stacks")) {
            settings.changed["stacks"].connect (load);
        }
        load ();
    }

    // The `stacks` key exists only in a schema built from our patch. A dock started in a
    // session that still points at an older schema directory (until the user logs back in
    // after a deploy) would abort inside GLib on get_value, so check first.
    public static Variant? read_stacks (Settings settings) {
        if (!settings.settings_schema.has_key ("stacks")) {
            warning ("The io.elementary.dock schema has no 'stacks' key (stale session schema?); showing no stacks");
            return null;
        }
        return settings.get_value ("stacks");
    }

    // Splices only the entries that changed, so editing one stack does not
    // rebuild every other stack's item.
    private void load () {
        var parsed = new GenericArray<StackConfig> ();
        var value = read_stacks (settings);
        if (value != null) {
            parsed = StackConfig.parse_all (value);
        }
        uint position, removed, added;
        StackList.changed_range (current, parsed, out position, out removed, out added);
        if (removed > 0 || added > 0) {
            Object[] items = {};
            for (uint i = position; i < position + added; i++) {
                items += parsed[i];
            }
            store.splice (position, removed, items);
        }
        current = parsed;
    }

    /* Adds a stack for the folder at path; false if it already has one. */
    public bool add (string path) {
        var list = StackList.with_added (current, path);
        if (list == null) {
            return false;
        }
        return save (list);
    }

    public void remove (string source) {
        save (StackList.with_removed (current, source));
    }

    public void update (string source, StackConfig.View view, StackConfig.Sort sort, StackConfig.Display display) {
        save (StackList.with_updated (current, source, view, sort, display));
    }

    public bool has_stack (string path) {
        return StackList.index_of (current, path) >= 0;
    }

    // The changed signal then reloads; nothing is spliced here.
    private bool save (GenericArray<StackConfig> list) {
        if (!settings.settings_schema.has_key ("stacks")) {
            warning ("The io.elementary.dock schema has no 'stacks' key (stale session schema?); not saving stacks");
            return false;
        }
        return settings.set_value ("stacks", StackList.to_variant (list));
    }
}
