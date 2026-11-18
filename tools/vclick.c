/*
 * vclick: move the pointer and optionally click, through the
 * wlr-virtual-pointer protocol. Test helper for the Expose overview.
 *
 *   vclick X Y [left|middle|right|none]
 *
 * Coordinates are in output pixels of a single 1280x720 (or other) output;
 * the extent is taken from the VCLICK_EXTENT env var, default 1280x720.
 */
#include <linux/input-event-codes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <wayland-client.h>
#include "wlr-virtual-pointer-unstable-v1-client-protocol.h"

/* Event timestamps in milliseconds. GTK ignores a menu release that follows
 * its press by no time at all, so zero timestamps would break menu clicks. */
static uint32_t
now_ms(void)
{
	struct timespec ts;
	clock_gettime(CLOCK_MONOTONIC, &ts);
	return (uint32_t)(ts.tv_sec * 1000 + ts.tv_nsec / 1000000);
}

static struct wl_seat *seat;
static struct zwlr_virtual_pointer_manager_v1 *manager;

static void
handle_global(void *data, struct wl_registry *registry, uint32_t name,
		const char *interface, uint32_t version)
{
	if (strcmp(interface, wl_seat_interface.name) == 0) {
		seat = wl_registry_bind(registry, name, &wl_seat_interface, 1);
	} else if (strcmp(interface,
			zwlr_virtual_pointer_manager_v1_interface.name) == 0) {
		manager = wl_registry_bind(registry, name,
			&zwlr_virtual_pointer_manager_v1_interface, 1);
	}
}

static void
handle_global_remove(void *data, struct wl_registry *registry, uint32_t name)
{
}

static const struct wl_registry_listener registry_listener = {
	.global = handle_global,
	.global_remove = handle_global_remove,
};

int
main(int argc, char **argv)
{
	if (argc < 3) {
		fprintf(stderr, "usage: vclick X Y [left|middle|right|none]\n");
		return 2;
	}
	unsigned int x = atoi(argv[1]), y = atoi(argv[2]);
	unsigned int ext_w = 1280, ext_h = 720;
	const char *extent = getenv("VCLICK_EXTENT");
	if (extent) {
		sscanf(extent, "%ux%u", &ext_w, &ext_h);
	}
	const char *which = argc > 3 ? argv[3] : "left";
	uint32_t button = BTN_LEFT;
	if (!strcmp(which, "middle")) {
		button = BTN_MIDDLE;
	} else if (!strcmp(which, "right")) {
		button = BTN_RIGHT;
	}

	struct wl_display *display = wl_display_connect(NULL);
	if (!display) {
		fprintf(stderr, "cannot connect to display\n");
		return 1;
	}
	struct wl_registry *registry = wl_display_get_registry(display);
	wl_registry_add_listener(registry, &registry_listener, NULL);
	wl_display_roundtrip(display);
	if (!manager || !seat) {
		fprintf(stderr, "virtual pointer protocol not available\n");
		return 1;
	}
	struct zwlr_virtual_pointer_v1 *pointer =
		zwlr_virtual_pointer_manager_v1_create_virtual_pointer(manager,
			seat);
	zwlr_virtual_pointer_v1_motion_absolute(pointer, now_ms(), x, y, ext_w, ext_h);
	zwlr_virtual_pointer_v1_frame(pointer);
	wl_display_roundtrip(display);
	usleep(100 * 1000);
	if (strcmp(which, "none") != 0) {
		zwlr_virtual_pointer_v1_button(pointer, now_ms(), button,
			WL_POINTER_BUTTON_STATE_PRESSED);
		zwlr_virtual_pointer_v1_frame(pointer);
		wl_display_roundtrip(display);
		usleep(50 * 1000);
		zwlr_virtual_pointer_v1_button(pointer, now_ms(), button,
			WL_POINTER_BUTTON_STATE_RELEASED);
		zwlr_virtual_pointer_v1_frame(pointer);
		wl_display_roundtrip(display);
	}
	zwlr_virtual_pointer_v1_destroy(pointer);
	wl_display_roundtrip(display);
	wl_display_disconnect(display);
	return 0;
}
