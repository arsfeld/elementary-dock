/*
 * SPDX-License-Identifier: GPL-3.0
 * SPDX-FileCopyrightText: 2025 elementary, Inc. (https://elementary.io)
 *
 * Authored by: Leonhard Kargl <leo.kargl@proton.me>
 */

 public class Dock.ItemGroup : Gtk.Widget {
    private const string OBJECT_DATA_KEY = "item-group-obj";

    [CCode (has_target = false)]
    public delegate BaseItem CreateBaseItemFunc (Object obj);

    private static Settings settings;

    public ListModel items { get; construct; }
    public CreateBaseItemFunc create_item_func { get; construct; }

    private Sequence<BaseItem> item_store;
    private ListStore current_children;

    private Adw.TimedAnimation resize_animation;

    private bool relayout_queued = false;

    /** Emitted when items are added to or removed from the group, so the zoom can be redone. */
    public signal void children_changed ();

    /** Width with every item at zoom 1, animated as items are added and removed. */
    public double rest_width { get; set; default = 0.0; }

    /** Extra width the current zoom adds on top of rest_width. */
    private double zoom_extra = 0.0;

    private HashTable<Object, BaseItem> cached_items;
    private uint clear_cache_id = 0;

    public ItemGroup (ListModel items, CreateBaseItemFunc create_item_func) {
        Object (items: items, create_item_func: create_item_func);
    }

    static construct {
        settings = new Settings ("io.elementary.dock");
    }

    construct {
        item_store = new Sequence<BaseItem> ();
        // Before the first on_items_changed: a model that already holds items looks them up here.
        cached_items = new HashTable<Object, BaseItem> (null, null);

        current_children = new ListStore (typeof (BaseItem));
        current_children.items_changed.connect (queue_relayout);
        current_children.items_changed.connect (notify_index_changed);
        current_children.items_changed.connect (emit_children_changed);

        settings.changed["icon-size"].connect (queue_relayout);

        var animation_target = new Adw.PropertyAnimationTarget (this, "rest-width");
        notify["rest-width"].connect (update_width);

        resize_animation = new Adw.TimedAnimation (this, 0, 0, Granite.TRANSITION_DURATION_OPEN, animation_target);
        resize_animation.done.connect (on_resized);

        items.items_changed.connect (on_items_changed);
        on_items_changed (0, 0, items.get_n_items ());

        overflow = VISIBLE;
    }

    // Not a Gtk.Fixed: GtkFixedLayout measures children through their transforms in both
    // directions, and an item scaled about its icon's bottom pushes its indicator strip
    // below the group. That made the group, and through MainWindow's size group the whole
    // dock, taller, and lifted every resting icon. Items always sit at y 0, so the height
    // is the resting one; the width is the transformed extent, as GtkFixedLayout had it.
    public override void measure (Gtk.Orientation orientation, int for_size, out int minimum, out int natural, out int minimum_baseline, out int natural_baseline) {
        minimum = 0;
        natural = 0;
        minimum_baseline = -1;
        natural_baseline = -1;

        for (var child = get_first_child (); child != null; child = child.get_next_sibling ()) {
            if (!child.should_layout ()) {
                continue;
            }

            Gtk.Requisition child_size;
            child.get_preferred_size (null, out child_size);

            var extent = child_size.height;
            if (orientation == HORIZONTAL) {
                var bounds = get_item_transform ((BaseItem) child, child_size.height).transform_bounds (
                    Graphene.Rect () { size = { child_size.width, child_size.height } }
                );
                extent = (int) Math.ceil (bounds.origin.x + bounds.size.width);
            }

            minimum = int.max (minimum, extent);
            natural = int.max (natural, extent);
        }
    }

    public override void size_allocate (int width, int height, int baseline) {
        for (var child = get_first_child (); child != null; child = child.get_next_sibling ()) {
            if (!child.should_layout ()) {
                continue;
            }

            Gtk.Requisition child_size;
            child.get_preferred_size (null, out child_size);
            child.allocate (child_size.width, child_size.height, -1, get_item_transform ((BaseItem) child, child_size.height));
        }
    }

    public override void dispose () {
        for (var child = get_first_child (); child != null; child = get_first_child ()) {
            child.unparent ();
        }

        base.dispose ();
    }

    private void queue_relayout () {
        if (relayout_queued) {
            return;
        }

        relayout_queued = true;
        Idle.add_once (relayout);
    }

    private void relayout () {
        resize_animation.value_from = rest_width;
        resize_animation.value_to = get_launcher_size () * current_children.get_n_items ();
        resize_animation.duration = resize_animation.value_from < resize_animation.value_to ?
            Granite.TRANSITION_DURATION_OPEN : Granite.TRANSITION_DURATION_CLOSE;
        resize_animation.play ();

        for (uint i = 0; i < current_children.get_n_items (); i++) {
            var item = (BaseItem) current_children.get_item (i);
            item.animate_move (get_launcher_size () * i);
        }

        relayout_queued = false;
    }

    private static int get_launcher_size () {
        return settings.get_int ("icon-size") + Launcher.PADDING * 2;
    }

    private void update_width () {
        width_request = (int) Math.round (rest_width + zoom_extra);
    }

    /**
     * Sets every item's zoom from its resting centre and lays the group out
     * again. offset is this group's resting x inside the ItemManager.
     */
    public void apply_zoom (ZoomController zoom, double offset) {
        var slot = get_launcher_size ();

        zoom_extra = 0.0;
        for (uint i = 0; i < current_children.get_n_items (); i++) {
            var item = (BaseItem) current_children.get_item (i);
            item.zoom = zoom.factor_at (offset + item.current_pos + slot / 2.0);
            zoom_extra += slot * (item.zoom - 1.0);
        }

        update_width ();

        queue_allocate ();
    }

    /**
     * Lays the group out again after an item's current_pos changed. The group
     * positions every item at once, so item is not used.
     */
    public void place_item (BaseItem item) {
        queue_allocate ();
    }

    /**
     * Puts item at its resting position plus the extra width of every
     * magnified item before it, scaled about its icon's bottom centre so it
     * grows up into the headroom above the dock.
     */
    private Gsk.Transform get_item_transform (BaseItem item, int item_height) {
        var slot = get_launcher_size ();

        var extra_before = 0.0;
        for (uint i = 0; i < current_children.get_n_items (); i++) {
            var other = (BaseItem) current_children.get_item (i);
            if (other == item) {
                break;
            }

            extra_before += slot * (other.zoom - 1.0);
        }

        var x = item.current_pos + extra_before;
        var factor = item.zoom;
        if (factor == 1.0) {
            return new Gsk.Transform ().translate (Graphene.Point () { x = (float) x });
        }

        var pivot_y = (float) item.get_icon_bottom (item_height);
        return new Gsk.Transform ()
            .translate (Graphene.Point () { x = (float) (x + slot * factor / 2.0), y = pivot_y })
            .scale ((float) factor, (float) factor)
            .translate (Graphene.Point () { x = (float) (-slot / 2.0), y = -pivot_y });
    }

    private void on_resized () {
        // When we finished resizing we know we now have enough space for all new items
        // so reveal them
        for (uint i = 0; i < current_children.get_n_items (); i++) {
            var item = (BaseItem) current_children.get_item (i);
            if (!item.visible) {
                item.visible = true;
                item.set_revealed (true);
            }
        }
    }

    private void on_items_changed (uint position, uint removed, uint added) {
        var start_iter = item_store.get_iter_at_pos ((int) position);
        var end_iter = start_iter.move ((int) removed);
        start_iter.foreach_range (end_iter, cache_item);
        start_iter.foreach_range (end_iter, remove_item);
        start_iter.remove_range (end_iter);

        var insert_iter = item_store.get_iter_at_pos ((int) position);
        for (int i = (int) position; i < position + added; i++) {
            var item = get_or_create_item (items.get_item (i));
            insert_iter.insert_before (item);

            add_item (i, item);
        }
    }

    // Make sure that if an item is removed and added again in the same
    // mainloop iteration it gets mapped to the same BaseItem
    private void cache_item (BaseItem item) {
        cached_items[item.get_data<Object> (OBJECT_DATA_KEY)] = item;

        if (clear_cache_id == 0) {
            clear_cache_id = Idle.add_once (clear_cache);
        }
    }

    private void clear_cache () {
        cached_items.remove_all ();
        clear_cache_id = 0;
    }

    private BaseItem get_or_create_item (Object obj) {
        if (obj in cached_items) {
            return cached_items[obj];
        }

        var base_item = create_item_func (obj);
        base_item.set_data<Object> (OBJECT_DATA_KEY, obj);
        return base_item;
    }

    private void add_item (int pos, BaseItem item) {
        if (item.parent == this) {
            // The item was already in this group and is currently being removed
            // so immediately finish the removal and add it as if it was new
            // This happens when the items are repositioned via dnd
            finish_remove (item);
        }

        item.visible = false;

        var item_pos = get_launcher_size () * pos;
        item.set_parent (this);
        item.current_pos = item_pos;
        place_item (item);

        current_children.insert (pos, item);
    }

    private void remove_item (BaseItem item) {
        item.revealed_done.connect (finish_remove);
        item.set_revealed (false);

        cached_items[item.get_data<Object> ("dock-obj")] = item;
    }

    private void finish_remove (BaseItem item) {
        item.revealed_done.disconnect (finish_remove);

        item.unparent ();

        uint index;
        if (current_children.find (item, out index)) {
            current_children.remove (index);
        }
    }

    private void emit_children_changed () {
        children_changed ();
    }

    private void notify_index_changed () {
        for (uint i = 0; i < current_children.get_n_items (); i++) {
            ((BaseItem) current_children.get_item (i)).index_changed ();
        }
    }

    public uint get_index_for_item (BaseItem item) {
        uint index;
        if (current_children.find (item, out index)) {
            return index;
        }

        return Gtk.INVALID_LIST_POSITION;
    }
}
