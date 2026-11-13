/*
 * SPDX-License-Identifier: GPL-3.0
 *
 * Edits to the list of stacks, and its io.elementary.dock `stacks` value.
 * Display-free and Settings-free, so the unit test covers it; StackStore
 * writes what these return.
 */

public class Dock.StackList {
    /* path with ~/ expanded and trailing slashes, `.` and `..` dropped. */
    public static string normalize (string path) {
        var expanded = path.has_prefix ("~/")
            ? Path.build_filename (Environment.get_home_dir (), path.substring (2))
            : path;
        return File.new_for_path (expanded).get_path ();
    }

    /* The index of the stack showing path, or -1. */
    public static int index_of (GenericArray<StackConfig> list, string path) {
        var wanted = path == StackConfig.APPLICATIONS ? path : normalize (path);
        for (int i = 0; i < list.length; i++) {
            if (list[i].source == wanted) {
                return i;
            }
        }
        return -1;
    }

    /* list plus a stack for path with the defaults for a dropped folder, or null if it has one. */
    public static GenericArray<StackConfig>? with_added (GenericArray<StackConfig> list, string path) {
        if (index_of (list, path) >= 0) {
            return null;
        }
        var result = copy (list);
        result.add (new StackConfig (normalize (path), FAN, DATE_ADDED, STACK));
        return result;
    }

    public static GenericArray<StackConfig> with_removed (GenericArray<StackConfig> list, string source) {
        var result = new GenericArray<StackConfig> ();
        foreach (var config in list) {
            if (config.source != source) {
                result.add (config);
            }
        }
        return result;
    }

    /* list with source's entry replaced; the other entries are the same objects. */
    public static GenericArray<StackConfig> with_updated (
        GenericArray<StackConfig> list, string source,
        StackConfig.View view, StackConfig.Sort sort, StackConfig.Display display
    ) {
        var result = new GenericArray<StackConfig> ();
        foreach (var config in list) {
            result.add (config.source == source ? new StackConfig (source, view, sort, display) : config);
        }
        return result;
    }

    public static Variant to_variant (GenericArray<StackConfig> list) {
        var builder = new VariantBuilder (new VariantType ("a(ssss)"));
        foreach (var config in list) {
            builder.add_value (config.to_variant ());
        }
        return builder.end ();
    }

    /*
     * The range that differs between old_list and new_list: everything before
     * position and after the last `added` new entries is unchanged, compared
     * with same_as. A ListStore splice of that range keeps every other item.
     */
    public static void changed_range (
        GenericArray<StackConfig> old_list, GenericArray<StackConfig> new_list,
        out uint position, out uint removed, out uint added
    ) {
        var shorter = uint.min (old_list.length, new_list.length);
        uint prefix = 0;
        while (prefix < shorter && old_list[prefix].same_as (new_list[prefix])) {
            prefix++;
        }
        uint suffix = 0;
        while (suffix < shorter - prefix
               && old_list[old_list.length - 1 - suffix].same_as (new_list[new_list.length - 1 - suffix])) {
            suffix++;
        }
        position = prefix;
        removed = old_list.length - prefix - suffix;
        added = new_list.length - prefix - suffix;
    }

    private static GenericArray<StackConfig> copy (GenericArray<StackConfig> list) {
        var result = new GenericArray<StackConfig> ();
        foreach (var config in list) {
            result.add (config);
        }
        return result;
    }
}
