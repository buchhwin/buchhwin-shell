// Virtual keyboard for nested test sessions (zwp_virtual_keyboard_manager_v1):
// key presses the compositor treats like a real keyboard's, binds included.
// Only ever start it through scripts/nested-keys, which refuses to run outside
// a session started by scripts/nested-session.sh. As a second safety line the
// tool itself refuses unless the named output exists; the real session has no
// BUCHTEST output.
//
//   nested-keys --output NAME COMMAND...
//
//   combo MODS+KEY     press the modifiers, tap the key, let go in reverse
//   down KEY | up KEY  one key (a modifier stays held between commands)
//   sleep MS
// KEY: a-z, 0-9, TAB, RETURN, ESCAPE, PERIOD, SPACE, F1-F12, SUPER, ALT,
// ALT_L, SHIFT, CTRL. Layout us.

#define _POSIX_C_SOURCE 200809L
#define _GNU_SOURCE
#include <ctype.h>
#include <linux/input-event-codes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>
#include <wayland-client.h>
#include <xkbcommon/xkbcommon.h>

#include "virtual-keyboard-unstable-v1-client-protocol.h"

struct output {
  struct wl_output *handle;
  char *name;
  struct output *next;
};

static struct wl_display *display;
static struct wl_seat *seat;
static struct zwp_virtual_keyboard_manager_v1 *manager;
static struct zwp_virtual_keyboard_v1 *keyboard;
static struct output *outputs;
static struct xkb_keymap *keymap;
static uint32_t depressed;

static void output_geometry(void *d, struct wl_output *o, int32_t x, int32_t y, int32_t pw, int32_t ph, int32_t s,
                            const char *make, const char *model, int32_t t) {
  (void)d, (void)o, (void)x, (void)y, (void)pw, (void)ph, (void)s, (void)make, (void)model, (void)t;
}
static void output_mode(void *d, struct wl_output *o, uint32_t f, int32_t w, int32_t h, int32_t r) {
  (void)d, (void)o, (void)f, (void)w, (void)h, (void)r;
}
static void output_done(void *d, struct wl_output *o) { (void)d, (void)o; }
static void output_scale(void *d, struct wl_output *o, int32_t f) { (void)d, (void)o, (void)f; }
static void output_name(void *data, struct wl_output *o, const char *name) {
  (void)o;
  struct output *entry = data;
  free(entry->name);
  entry->name = strdup(name);
}
static void output_description(void *d, struct wl_output *o, const char *s) { (void)d, (void)o, (void)s; }
static const struct wl_output_listener output_listener = {output_geometry, output_mode, output_done,
                                                          output_scale, output_name, output_description};

static void registry_global(void *data, struct wl_registry *registry, uint32_t name, const char *interface,
                            uint32_t version) {
  (void)data;
  if (strcmp(interface, wl_seat_interface.name) == 0 && !seat) {
    seat = wl_registry_bind(registry, name, &wl_seat_interface, 1);
  } else if (strcmp(interface, zwp_virtual_keyboard_manager_v1_interface.name) == 0) {
    manager = wl_registry_bind(registry, name, &zwp_virtual_keyboard_manager_v1_interface, 1);
  } else if (strcmp(interface, wl_output_interface.name) == 0 && version >= 4) {
    struct output *entry = calloc(1, sizeof *entry);
    entry->handle = wl_registry_bind(registry, name, &wl_output_interface, 4);
    entry->next = outputs;
    outputs = entry;
    wl_output_add_listener(entry->handle, &output_listener, entry);
  }
}
static void registry_global_remove(void *d, struct wl_registry *r, uint32_t n) { (void)d, (void)r, (void)n; }
static const struct wl_registry_listener registry_listener = {registry_global, registry_global_remove};

static void sleep_ms(long ms) {
  struct timespec ts = {ms / 1000, (ms % 1000) * 1000000L};
  nanosleep(&ts, NULL);
}

static uint32_t now_ms(void) {
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return (uint32_t)(ts.tv_sec * 1000 + ts.tv_nsec / 1000000);
}

struct named_key {
  const char *name;
  int code;
  const char *mod; // xkb modifier the key holds, or NULL
};

static const struct named_key named[] = {
  {"SUPER", KEY_LEFTMETA, XKB_MOD_NAME_LOGO}, {"ALT", KEY_LEFTALT, XKB_MOD_NAME_ALT},
  {"ALT_L", KEY_LEFTALT, XKB_MOD_NAME_ALT},  {"SHIFT", KEY_LEFTSHIFT, XKB_MOD_NAME_SHIFT},
  {"CTRL", KEY_LEFTCTRL, XKB_MOD_NAME_CTRL}, {"TAB", KEY_TAB, NULL},
  {"RETURN", KEY_ENTER, NULL},               {"ESCAPE", KEY_ESC, NULL},
  {"PERIOD", KEY_DOT, NULL},                 {"SPACE", KEY_SPACE, NULL},
  {"UP", KEY_UP, NULL},                      {"DOWN", KEY_DOWN, NULL},
  {"LEFT", KEY_LEFT, NULL},                  {"RIGHT", KEY_RIGHT, NULL},
  // The neighbouring workspace, the zoom and the drop-down terminal's key
  // (the one left of 1, bound by its place as code:49).
  {"PAGEUP", KEY_PAGEUP, NULL},              {"PAGEDOWN", KEY_PAGEDOWN, NULL},
  {"MINUS", KEY_MINUS, NULL},                {"EQUAL", KEY_EQUAL, NULL},
  {"GRAVE", KEY_GRAVE, NULL},
};

static int key_code(const char *name, const char **mod) {
  *mod = NULL;
  for (size_t i = 0; i < sizeof named / sizeof *named; ++i)
    if (strcasecmp(name, named[i].name) == 0) {
      *mod = named[i].mod;
      return named[i].code;
    }
  if (strlen(name) == 1) {
    static const int letters[] = {KEY_A, KEY_B, KEY_C, KEY_D, KEY_E, KEY_F, KEY_G, KEY_H, KEY_I,
                                  KEY_J, KEY_K, KEY_L, KEY_M, KEY_N, KEY_O, KEY_P, KEY_Q, KEY_R,
                                  KEY_S, KEY_T, KEY_U, KEY_V, KEY_W, KEY_X, KEY_Y, KEY_Z};
    static const int digits[] = {KEY_0, KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9};
    char c = (char)tolower((unsigned char)name[0]);
    if (c >= 'a' && c <= 'z') return letters[c - 'a'];
    if (c >= '0' && c <= '9') return digits[c - '0'];
  }
  if ((name[0] == 'F' || name[0] == 'f') && atoi(name + 1) >= 1 && atoi(name + 1) <= 12) {
    static const int fkeys[] = {KEY_F1, KEY_F2, KEY_F3, KEY_F4, KEY_F5, KEY_F6,
                                KEY_F7, KEY_F8, KEY_F9, KEY_F10, KEY_F11, KEY_F12};
    return fkeys[atoi(name + 1) - 1];
  }
  return -1;
}

static int send_key(const char *name, int pressed) {
  const char *mod;
  int code = key_code(name, &mod);
  if (code < 0) {
    fprintf(stderr, "nested-keys: unknown key '%s'\n", name);
    return -1;
  }
  zwp_virtual_keyboard_v1_key(keyboard, now_ms(), (uint32_t)code,
                              pressed ? WL_KEYBOARD_KEY_STATE_PRESSED : WL_KEYBOARD_KEY_STATE_RELEASED);
  if (mod) {
    xkb_mod_index_t index = xkb_keymap_mod_get_index(keymap, mod);
    if (index != XKB_MOD_INVALID) {
      if (pressed) depressed |= 1u << index;
      else depressed &= ~(1u << index);
      zwp_virtual_keyboard_v1_modifiers(keyboard, depressed, 0, 0, 0);
    }
  }
  wl_display_roundtrip(display);
  return 0;
}

static int combo(const char *text) {
  char buffer[128];
  snprintf(buffer, sizeof buffer, "%s", text);
  char *parts[8];
  int count = 0;
  for (char *part = strtok(buffer, "+"); part && count < 8; part = strtok(NULL, "+")) parts[count++] = part;
  for (int i = 0; i < count; ++i)
    if (send_key(parts[i], 1) < 0) return -1;
  sleep_ms(20);
  for (int i = count - 1; i >= 0; --i) send_key(parts[i], 0);
  return 0;
}

static int upload_keymap(void) {
  struct xkb_context *context = xkb_context_new(XKB_CONTEXT_NO_FLAGS);
  struct xkb_rule_names names = {"evdev", "pc105", "us", "", ""};
  keymap = context ? xkb_keymap_new_from_names(context, &names, XKB_KEYMAP_COMPILE_NO_FLAGS) : NULL;
  if (!keymap) return -1;
  char *text = xkb_keymap_get_as_string(keymap, XKB_KEYMAP_FORMAT_TEXT_V1);
  size_t size = strlen(text) + 1;
  int fd = memfd_create("nested-keys-keymap", MFD_CLOEXEC);
  if (fd < 0 || ftruncate(fd, (off_t)size) < 0) return -1;
  char *map = mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
  if (map == MAP_FAILED) return -1;
  memcpy(map, text, size);
  munmap(map, size);
  free(text);
  zwp_virtual_keyboard_v1_keymap(keyboard, WL_KEYBOARD_KEYMAP_FORMAT_XKB_V1, (uint32_t)fd, (uint32_t)size);
  wl_display_roundtrip(display);
  return 0;
}

int main(int argc, char **argv) {
  const char *output_name_arg = NULL;
  int i = 1;
  if (i + 1 < argc && strcmp(argv[i], "--output") == 0) {
    output_name_arg = argv[i + 1];
    i += 2;
  }
  if (!output_name_arg || i >= argc) {
    fprintf(stderr, "usage: nested-keys --output NAME combo MODS+KEY | down KEY | up KEY | sleep MS ...\n");
    return 2;
  }
  display = wl_display_connect(NULL);
  if (!display) {
    fprintf(stderr, "nested-keys: no Wayland display\n");
    return 1;
  }
  wl_registry_add_listener(wl_display_get_registry(display), &registry_listener, NULL);
  wl_display_roundtrip(display);
  wl_display_roundtrip(display);
  int found = 0;
  for (struct output *o = outputs; o; o = o->next)
    if (o->name && strcmp(o->name, output_name_arg) == 0) found = 1;
  if (!found) {
    fprintf(stderr, "nested-keys: no output %s here; refusing (not a nested session?)\n", output_name_arg);
    return 1;
  }
  if (!seat || !manager) {
    fprintf(stderr, "nested-keys: the compositor offers no virtual keyboard\n");
    return 1;
  }
  keyboard = zwp_virtual_keyboard_manager_v1_create_virtual_keyboard(manager, seat);
  if (upload_keymap() < 0) {
    fprintf(stderr, "nested-keys: could not build the keymap\n");
    return 1;
  }
  for (; i < argc; ++i) {
    if (strcmp(argv[i], "combo") == 0 && i + 1 < argc) {
      if (combo(argv[++i]) < 0) return 1;
    } else if ((strcmp(argv[i], "down") == 0 || strcmp(argv[i], "up") == 0) && i + 1 < argc) {
      int pressed = argv[i][0] == 'd';
      if (send_key(argv[++i], pressed) < 0) return 1;
    } else if (strcmp(argv[i], "sleep") == 0 && i + 1 < argc) {
      sleep_ms(atol(argv[++i]));
    } else {
      fprintf(stderr, "nested-keys: unknown command '%s'\n", argv[i]);
      return 2;
    }
  }
  wl_display_roundtrip(display);
  zwp_virtual_keyboard_v1_destroy(keyboard);
  wl_display_flush(display);
  return 0;
}
