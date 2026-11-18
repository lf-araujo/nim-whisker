/*
 * vkey: send key presses through the virtual-keyboard protocol with real
 * timestamps. Test helper. (wtype sends every event with time 0, which GTK
 * popup menus do not act on.)
 *
 *   vkey Down Tab Return        press and release each named key in turn
 *   vkey -t "some text"         type the characters of a string
 *
 * Key names are xkb keysym names (Down, Tab, Return, Escape, a, ...).
 */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>
#include <wayland-client.h>
#include <xkbcommon/xkbcommon.h>
#include "virtual-keyboard-unstable-v1-client-protocol.h"

static struct wl_seat *seat;
static struct zwp_virtual_keyboard_manager_v1 *manager;

static void
handle_global(void *data, struct wl_registry *registry, uint32_t name,
		const char *interface, uint32_t version)
{
	if (strcmp(interface, wl_seat_interface.name) == 0) {
		seat = wl_registry_bind(registry, name, &wl_seat_interface, 1);
	} else if (strcmp(interface,
			zwp_virtual_keyboard_manager_v1_interface.name) == 0) {
		manager = wl_registry_bind(registry, name,
			&zwp_virtual_keyboard_manager_v1_interface, 1);
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

static uint32_t
now_ms(void)
{
	struct timespec ts;
	clock_gettime(CLOCK_MONOTONIC, &ts);
	return (uint32_t)(ts.tv_sec * 1000 + ts.tv_nsec / 1000000);
}

/* evdev code of the key that produces `sym` in the default layout, or -1 */
static int
keycode_for(struct xkb_keymap *keymap, struct xkb_state *state, xkb_keysym_t sym,
		int *needs_shift)
{
	for (int shift = 0; shift < 2; shift++) {
		xkb_state_update_mask(state, shift ? 1 : 0, 0, 0, 0, 0, 0);
		for (xkb_keycode_t code = 8; code < 256; code++) {
			if (xkb_state_key_get_one_sym(state, code) == sym) {
				*needs_shift = shift;
				return (int)code - 8;
			}
		}
	}
	return -1;
}

int
main(int argc, char **argv)
{
	if (argc < 2) {
		fprintf(stderr, "usage: vkey KEYNAME... | vkey -t TEXT\n");
		return 2;
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
		fprintf(stderr, "virtual keyboard protocol not available\n");
		return 1;
	}

	struct xkb_context *context = xkb_context_new(XKB_CONTEXT_NO_FLAGS);
	struct xkb_rule_names names = { .layout = "us" };
	struct xkb_keymap *keymap = xkb_keymap_new_from_names(context, &names,
		XKB_KEYMAP_COMPILE_NO_FLAGS);
	struct xkb_state *state = xkb_state_new(keymap);
	char *text = xkb_keymap_get_as_string(keymap, XKB_KEYMAP_FORMAT_TEXT_V1);
	size_t size = strlen(text) + 1;
	int fd = memfd_create("vkey-keymap", 0);
	ftruncate(fd, size);
	void *map = mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
	memcpy(map, text, size);

	struct zwp_virtual_keyboard_v1 *keyboard =
		zwp_virtual_keyboard_manager_v1_create_virtual_keyboard(manager, seat);
	zwp_virtual_keyboard_v1_keymap(keyboard, WL_KEYBOARD_KEYMAP_FORMAT_XKB_V1,
		fd, size);
	wl_display_roundtrip(display);
	usleep(250 * 1000); /* let the client switch keymaps before the first key */

	int type_text = strcmp(argv[1], "-t") == 0;
	int count = type_text ? (int)strlen(argv[2]) : argc - 1;
	for (int i = 0; i < count; i++) {
		xkb_keysym_t sym;
		if (type_text) {
			char name[2] = { argv[2][i], 0 };
			sym = xkb_utf32_to_keysym((uint32_t)(unsigned char)name[0]);
		} else {
			sym = xkb_keysym_from_name(argv[1 + i], XKB_KEYSYM_CASE_INSENSITIVE);
		}
		int shift = 0;
		int code = keycode_for(keymap, state, sym, &shift);
		if (code < 0) {
			fprintf(stderr, "no key for %s\n", type_text ? argv[2] : argv[1 + i]);
			continue;
		}
		if (shift) {
			zwp_virtual_keyboard_v1_modifiers(keyboard, 1, 0, 0, 0);
		}
		zwp_virtual_keyboard_v1_key(keyboard, now_ms(), code,
			WL_KEYBOARD_KEY_STATE_PRESSED);
		wl_display_roundtrip(display);
		usleep(40 * 1000);
		zwp_virtual_keyboard_v1_key(keyboard, now_ms(), code,
			WL_KEYBOARD_KEY_STATE_RELEASED);
		if (shift) {
			zwp_virtual_keyboard_v1_modifiers(keyboard, 0, 0, 0, 0);
		}
		wl_display_roundtrip(display);
		usleep(60 * 1000);
	}
	zwp_virtual_keyboard_v1_destroy(keyboard);
	wl_display_roundtrip(display);
	wl_display_disconnect(display);
	return 0;
}
