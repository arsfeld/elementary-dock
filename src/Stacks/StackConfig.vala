/*
 * SPDX-License-Identifier: GPL-3.0
 *
 * One entry of the io.elementary.dock `stacks` key, validated.
 */

namespace Dock {
    public errordomain StackConfigError {
        INVALID
    }
}

public class Dock.StackConfig : Object {
    public enum View { FAN, GRID }
    public enum Sort { DATE_ADDED, NAME }
    public enum Display { STACK, GRID, FOLDER }

    public const string APPLICATIONS = "applications";

    /* An absolute path, or APPLICATIONS. */
    public string source { get; construct; }
    public View view { get; construct; }
    public Sort sort { get; construct; }
    public Display display { get; construct; }

    // The key's spelling of each enum value, indexed by the value: parse and
    // to_variant both read these, so the two stay inverse.
    private const string[] VIEW_NAMES = { "fan", "grid" };
    private const string[] SORT_NAMES = { "date-added", "name" };
    private const string[] DISPLAY_NAMES = { "stack", "grid", "folder" };

    public bool is_applications { get { return source == APPLICATIONS; } }

    public StackConfig (string source, View view, Sort sort, Display display) {
        Object (source: source, view: view, sort: sort, display: display);
    }

    public static StackConfig parse (string source, string view, string sort, string display) throws StackConfigError {
        // Normalized, so a stored `~/Downloads/` and a dropped `/home/u/Downloads`
        // are the same stack.
        string resolved;
        if (source == APPLICATIONS) {
            resolved = source;
        } else if (Path.is_absolute (source) || source.has_prefix ("~/")) {
            resolved = StackList.normalize (source);
        } else {
            throw new StackConfigError.INVALID ("source must be an absolute path, ~/…, or '%s'", APPLICATIONS);
        }

        View parsed_view = 0;
        if (!parse_name (view, VIEW_NAMES, ref parsed_view)) {
            throw new StackConfigError.INVALID ("unknown view '%s'", view);
        }
        Sort parsed_sort = 0;
        if (!parse_name (sort, SORT_NAMES, ref parsed_sort)) {
            throw new StackConfigError.INVALID ("unknown sort '%s'", sort);
        }
        Display parsed_display = 0;
        if (!parse_name (display, DISPLAY_NAMES, ref parsed_display)) {
            throw new StackConfigError.INVALID ("unknown display '%s'", display);
        }

        return new StackConfig (resolved, parsed_view, parsed_sort, parsed_display);
    }

    private static bool parse_name (string name, string[] names, ref int result) {
        for (int i = 0; i < names.length; i++) {
            if (names[i] == name) {
                result = i;
                return true;
            }
        }
        return false;
    }

    public static string view_name (View view) { return VIEW_NAMES[view]; }
    public static string sort_name (Sort sort) { return SORT_NAMES[sort]; }
    public static string display_name (Display display) { return DISPLAY_NAMES[display]; }

    /* source as the key stores it: ~/… under the home directory, else unchanged. */
    public string saved_source () {
        var home = Environment.get_home_dir ();
        if (source.has_prefix (home + "/")) {
            return "~/" + source.substring (home.length + 1);
        }
        return source;
    }

    /* This entry as one (ssss) child of the `stacks` key. */
    public Variant to_variant () {
        return new Variant ("(ssss)", saved_source (), view_name (view), sort_name (sort), display_name (display));
    }

    public bool same_as (StackConfig other) {
        return source == other.source && view == other.view && sort == other.sort && display == other.display;
    }

    /* Parses an a(ssss) value, logging and skipping invalid entries. */
    public static GenericArray<StackConfig> parse_all (Variant stacks) {
        var result = new GenericArray<StackConfig> ();
        for (size_t i = 0; i < stacks.n_children (); i++) {
            var entry = stacks.get_child_value (i);
            var source = entry.get_child_value (0).get_string ();
            try {
                result.add (parse (
                    source,
                    entry.get_child_value (1).get_string (),
                    entry.get_child_value (2).get_string (),
                    entry.get_child_value (3).get_string ()
                ));
            } catch (StackConfigError e) {
                warning ("Ignoring stack %s: %s", source, e.message);
            }
        }
        return result;
    }
}
