#include <unistd.h>
#include "network.h"
#include "../sketchybar.h"

int main(int argc, char **argv) {
  float update_freq;
  if (argc < 3 || (sscanf(argv[2], "%f", &update_freq) != 1)) {
    printf("Usage: %s \"<event-name>\" \"<event_freq>\"\n", argv[0]);
    exit(1);
  }

  alarm(0);

  /* Register the event with sketchybar */
  char event_message[512];
  snprintf(event_message, sizeof(event_message),
           "--add event '%s'", argv[1]);
  sketchybar(event_message);

  struct network net;
  memset(&net, 0, sizeof(net));

  char trigger_message[512];

  for (;;) {
    network_sample(&net);

    if (net.ifname[0] != '\0') {
      snprintf(trigger_message, sizeof(trigger_message),
               "--trigger '%s' upload='%03d%s' download='%03d%s' interface='%s'",
               argv[1],
               net.up,   unit_str[net.up_unit],
               net.down, unit_str[net.down_unit],
               net.ifname);
    } else {
      /* No usable interface found */
      snprintf(trigger_message, sizeof(trigger_message),
               "--trigger '%s' upload='000 Bps' download='000 Bps' interface='none'",
               argv[1]);
    }

    sketchybar(trigger_message);
    usleep((useconds_t)(update_freq * 1000000.f));
  }

  return 0;
}
