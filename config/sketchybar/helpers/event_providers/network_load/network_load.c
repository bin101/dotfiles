#include <unistd.h>
#include "network.h"
#include "../sketchybar.h"

int main (int argc, char** argv) {
  float update_freq;
  if (argc < 3 || (sscanf(argv[2], "%f", &update_freq) != 1)) {
    printf("Usage: %s \"<event-name>\" \"<event_freq>\"\n", argv[0]);
    exit(1);
  }

  alarm(0);
  // Setup the event in sketchybar
  char event_message[512];
  snprintf(event_message, 512, "--add event '%s'", argv[1]);
  sketchybar(event_message);

  struct network network;
  memset(&network, 0, sizeof(network));

  char current_ifname[32] = "";
  char trigger_message[512];

  for (;;) {
    // Auto-detect the current default network interface
    char detected_if[32] = "";
    if (get_default_interface(detected_if, sizeof(detected_if)) == 0) {
      // Re-initialize when interface changes
      if (strcmp(detected_if, current_ifname) != 0) {
        strncpy(current_ifname, detected_if, sizeof(current_ifname) - 1);
        network_init(&network, current_ifname);
      }

      // Acquire new info
      network_update(&network);

      // Prepare the event message (includes interface name)
      snprintf(trigger_message,
               512,
               "--trigger '%s' upload='%03d%s' download='%03d%s' interface='%s'",
               argv[1],
               network.up,
               unit_str[network.up_unit],
               network.down,
               unit_str[network.down_unit],
               current_ifname);

      // Trigger the event
      sketchybar(trigger_message);
    } else {
      // No default route / no network
      snprintf(trigger_message,
               512,
               "--trigger '%s' upload='000 Bps' download='000 Bps' interface='none'",
               argv[1]);
      sketchybar(trigger_message);
      current_ifname[0] = '\0';
    }

    // Wait
    usleep(update_freq * 1000000);
  }
  return 0;
}
