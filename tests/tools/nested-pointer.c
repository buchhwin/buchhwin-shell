// Virtual pointer for nested test sessions (zwlr_virtual_pointer_manager_v1).
// Only ever start it through scripts/nested-pointer, which refuses to run
// outside a session started by scripts/nested-session.sh. As a second safety
// line the tool itself refuses unless the named output exists; the real
// session has no BUCHTEST output.
//
//   nested-pointer --output NAME --extent WxH COMMAND...
//
// Coordinates are logical pixels of that output (the extent is its logical
// size). Commands run in order:
//   move X Y                  hover X Y MS             sleep MS
//   down [BUTTON]             up [BUTTON]              click [BUTTON] X Y
//   scroll DY X Y             drag X1 Y1 X2 Y2 [STEPS]
// BUTTON is left, right or middle; DY counts wheel notches (positive: down).

#define _POSIX_C_SOURCE 200809L
#include <errno.h>
#include <linux/input-event-codes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <wayland-client.h>

#include "wlr-virtual-pointer-unstable-v1-client-protocol.h"

// Sub-pixel precision for motion_absolute, which only takes integers.
static const unsigned kPrecision = 100;

struct output {
  struct wl_output *handle;
  char *name;
  struct output *next;
};

static struct wl_seat *seat;
static struct zwlr_virtual_pointer_manager_v1 *manager;
static uint32_t manager_version;
static struct output *outputs;
static struct zwlr_virtual_pointer_v1 *pointer;
static struct wl_display *display;
static double extent_w, extent_h;
static double pos_x, pos_y;

static void output_geometry(void *data, struct wl_output *o, int32_t x, int32_t y, int32_t pw, int32_t ph,
                            int32_t subpixel, const char *make, const char *model, int32_t transform) {
  (void)data, (void)o, (void)x, (void)y, (void)pw, (void)ph, (void)subpixel, (void)make, (void)model, (void)transform;
}
static void output_mode(void *data, struct wl_output *o, uint32_t flags, int32_t w, int32_t h, int32_t refresh) {
  (void)data, (void)o, (void)flags, (void)w, (void)h, (void)refresh;
}
static void output_done(void *data, struct wl_output *o) { (void)data, (void)o; }
static void output_scale(void *data, struct wl_output *o, int32_t factor) { (void)data, (void)o, (void)factor; }
static void output_name(void *data, struct wl_output *o, const char *name) {
  (void)o;
  struct output *entry = data;
  free(entry->name);
  entry->name = strdup(name);
}
static void output_description(void *data, struct wl_output *o, const char *description) {
  (void)data, (void)o, (void)description;
}

static const struct wl_output_listener output_listener = {
  .geometry = output_geometry,
  .mode = output_mode,
  .done = output_done,
  .scale = output_scale,
  .name = output_name,
  .description = output_description,
};

static void registry_global(void *data, struct wl_registry *registry, uint32_t name, const char *interface,
                            uint32_t version) {
  (void)data;
  if (strcmp(interface, wl_seat_interface.name) == 0 && !seat) {
    seat = wl_registry_bind(registry, name, &wl_seat_interface, 1);
  } else if (strcmp(interface, zwlr_virtual_pointer_manager_v1_interface.name) == 0) {
    manager_version = version < 2 ? version : 2;
    manager = wl_registry_bind(registry, name, &zwlr_virtual_pointer_manager_v1_interface, manager_version);
  } else if (strcmp(interface, wl_output_interface.name) == 0 && version >= 4) {
    struct output *entry = calloc(1, sizeof *entry);
    entry->handle = wl_registry_bind(registry, name, &wl_output_interface, 4);
    entry->next = outputs;
    outputs = entry;
    wl_output_add_listener(entry->handle, &output_listener, entry);
  }
}
static void registry_global_remove(void *data, struct wl_registry *registry, uint32_t name) {
  (void)data, (void)registry, (void)name;
}
static const struct wl_registry_listener registry_listener = {registry_global, registry_global_remove};

static uint32_t now_ms(void) {
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return (uint32_t)(ts.tv_sec * 1000 + ts.tv_nsec / 1000000);
}

static void sleep_ms(long ms) {
  if (ms <= 0) return;
  struct timespec ts = {ms / 1000, (ms % 1000) * 1000000};
  while (nanosleep(&ts, &ts) == -1 && errno == EINTR) {
  }
}

static void sync_frame(void) {
  zwlr_virtual_pointer_v1_frame(pointer);
  if (wl_display_roundtrip(display) < 0) {
    fprintf(stderr, "nested-pointer: connection lost\n");
    exit(1);
  }
}

static unsigned scaled(double value, double extent) {
  if (value < 0) value = 0;
  if (value > extent - 1) value = extent - 1;
  return (unsigned)(value * kPrecision + 0.5);
}

static void move_to(double x, double y) {
  pos_x = x, pos_y = y;
  zwlr_virtual_pointer_v1_motion_absolute(pointer, now_ms(), scaled(x, extent_w), scaled(y, extent_h),
                                          (unsigned)(extent_w * kPrecision), (unsigned)(extent_h * kPrecision));
  sync_frame();
}

static void button(uint32_t code, int pressed) {
  zwlr_virtual_pointer_v1_button(pointer, now_ms(), code,
                                 pressed ? WL_POINTER_BUTTON_STATE_PRESSED : WL_POINTER_BUTTON_STATE_RELEASED);
  sync_frame();
}

static int parse_button(const char *word, uint32_t *code) {
  if (!word) return 0;
  if (strcmp(word, "left") == 0) *code = BTN_LEFT;
  else if (strcmp(word, "right") == 0) *code = BTN_RIGHT;
  else if (strcmp(word, "middle") == 0) *code = BTN_MIDDLE;
  else return 0;
  return 1;
}

static int is_number(const char *word) {
  if (!word || !*word) return 0;
  char *end;
  strtod(word, &end);
  return *end == '\0';
}

static double number(char **argv, int argc, int *i) {
  if (*i >= argc || !is_number(argv[*i])) {
    fprintf(stderr, "nested-pointer: number expected at '%s'\n", *i < argc ? argv[*i] : "end");
    exit(2);
  }
  return strtod(argv[(*i)++], NULL);
}

static void usage(void) {
  fprintf(stderr, "Usage: nested-pointer --output NAME --extent WxH COMMAND...\n"
                  "  move X Y | hover X Y MS | sleep MS | down [BUTTON] | up [BUTTON]\n"
                  "  click [BUTTON] X Y | scroll NOTCHES X Y | drag X1 Y1 X2 Y2 [STEPS]\n"
                  "  scroll-finger PIXELS X Y [STEPS]   (touchpad-like, continuous)\n");
}

int main(int argc, char **argv) {
  const char *output_name_arg = NULL;
  int i = 1;
  for (; i < argc; i++) {
    if (strcmp(argv[i], "--output") == 0 && i + 1 < argc) {
      output_name_arg = argv[++i];
    } else if (strcmp(argv[i], "--extent") == 0 && i + 1 < argc) {
      if (sscanf(argv[++i], "%lfx%lf", &extent_w, &extent_h) != 2) extent_w = 0;
    } else {
      break;
    }
  }
  if (!output_name_arg || extent_w < 1 || extent_h < 1 || i >= argc) {
    usage();
    return 2;
  }

  display = wl_display_connect(NULL);
  if (!display) {
    fprintf(stderr, "nested-pointer: cannot connect to the Wayland display\n");
    return 1;
  }
  struct wl_registry *registry = wl_display_get_registry(display);
  wl_registry_add_listener(registry, &registry_listener, NULL);
  wl_display_roundtrip(display);
  wl_display_roundtrip(display);

  struct output *target = NULL;
  for (struct output *entry = outputs; entry; entry = entry->next)
    if (entry->name && strcmp(entry->name, output_name_arg) == 0) target = entry;
  if (!target) {
    fprintf(stderr, "nested-pointer: output %s not found; refusing\n", output_name_arg);
    return 4;
  }
  if (!manager || manager_version < 2) {
    fprintf(stderr, "nested-pointer: compositor lacks zwlr_virtual_pointer_manager_v1 v2\n");
    return 1;
  }
  pointer = zwlr_virtual_pointer_manager_v1_create_virtual_pointer_with_output(manager, seat, target->handle);
  wl_display_roundtrip(display);

  while (i < argc) {
    const char *command = argv[i++];
    uint32_t code = BTN_LEFT;
    if (strcmp(command, "move") == 0) {
      double x = number(argv, argc, &i), y = number(argv, argc, &i);
      move_to(x, y);
    } else if (strcmp(command, "hover") == 0) {
      double x = number(argv, argc, &i), y = number(argv, argc, &i);
      long ms = (long)number(argv, argc, &i);
      move_to(x, y);
      sleep_ms(ms);
    } else if (strcmp(command, "sleep") == 0) {
      sleep_ms((long)number(argv, argc, &i));
    } else if (strcmp(command, "down") == 0 || strcmp(command, "up") == 0) {
      if (i < argc && parse_button(argv[i], &code)) i++;
      button(code, command[0] == 'd');
    } else if (strcmp(command, "click") == 0) {
      if (i < argc && parse_button(argv[i], &code)) i++;
      double x = number(argv, argc, &i), y = number(argv, argc, &i);
      move_to(x, y);
      sleep_ms(40);
      button(code, 1);
      sleep_ms(40);
      button(code, 0);
      sleep_ms(40);
    } else if (strcmp(command, "scroll") == 0) {
      int notches = (int)number(argv, argc, &i);
      double x = number(argv, argc, &i), y = number(argv, argc, &i);
      move_to(x, y);
      sleep_ms(40);
      // A wheel click: the axis value belongs with the discrete step, and Qt
      // clients only scroll when both arrive in the same frame.
      zwlr_virtual_pointer_v1_axis_source(pointer, WL_POINTER_AXIS_SOURCE_WHEEL);
      zwlr_virtual_pointer_v1_axis(pointer, now_ms(), WL_POINTER_AXIS_VERTICAL_SCROLL,
                                   wl_fixed_from_double(15.0 * notches));
      zwlr_virtual_pointer_v1_axis_discrete(pointer, now_ms(), WL_POINTER_AXIS_VERTICAL_SCROLL,
                                            wl_fixed_from_double(15.0 * notches), notches);
      sync_frame();
      sleep_ms(40);
    } else if (strcmp(command, "scroll-finger") == 0) {
      // Touchpad-like scrolling: continuous axis events from a finger source,
      // ended with axis_stop - this is what the user's touchpad produces.
      double pixels = number(argv, argc, &i);
      double x = number(argv, argc, &i), y = number(argv, argc, &i);
      int steps = i < argc && is_number(argv[i]) ? (int)number(argv, argc, &i) : 8;
      if (steps < 1) steps = 1;
      move_to(x, y);
      sleep_ms(40);
      for (int step = 0; step < steps; step++) {
        zwlr_virtual_pointer_v1_axis_source(pointer, WL_POINTER_AXIS_SOURCE_FINGER);
        zwlr_virtual_pointer_v1_axis(pointer, now_ms(), WL_POINTER_AXIS_VERTICAL_SCROLL,
                                     wl_fixed_from_double(pixels / steps));
        sync_frame();
        sleep_ms(16);
      }
      zwlr_virtual_pointer_v1_axis_source(pointer, WL_POINTER_AXIS_SOURCE_FINGER);
      zwlr_virtual_pointer_v1_axis_stop(pointer, now_ms(), WL_POINTER_AXIS_VERTICAL_SCROLL);
      sync_frame();
      sleep_ms(40);
    } else if (strcmp(command, "drag") == 0) {
      double x1 = number(argv, argc, &i), y1 = number(argv, argc, &i);
      double x2 = number(argv, argc, &i), y2 = number(argv, argc, &i);
      int steps = i < argc && is_number(argv[i]) ? (int)number(argv, argc, &i) : 20;
      if (steps < 1) steps = 1;
      move_to(x1, y1);
      sleep_ms(40);
      button(BTN_LEFT, 1);
      sleep_ms(40);
      for (int step = 1; step <= steps; step++) {
        move_to(x1 + (x2 - x1) * step / steps, y1 + (y2 - y1) * step / steps);
        sleep_ms(12);
      }
      sleep_ms(40);
      button(BTN_LEFT, 0);
      sleep_ms(40);
    } else {
      fprintf(stderr, "nested-pointer: unknown command '%s'\n", command);
      usage();
      return 2;
    }
  }

  zwlr_virtual_pointer_v1_destroy(pointer);
  wl_display_roundtrip(display);
  wl_display_disconnect(display);
  return 0;
}
