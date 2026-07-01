#include <math.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <net/if.h>
#include <net/if_mib.h>
#include <sys/time.h>
#include <sys/sysctl.h>

static char unit_str[3][6] = { { " Bps" }, { "KBps" }, { "MBps" }, };

enum unit {
  UNIT_BPS,
  UNIT_KBPS,
  UNIT_MBPS
};

#define MAX_IFACES 64

/* Per-interface snapshot from the previous sampling cycle */
struct ifsnap {
  char     name[IF_NAMESIZE];
  uint64_t ibytes;
  uint64_t obytes;
  int      valid; /* 1 once we have a previous sample */
};

struct network {
  /* Result for the chosen interface */
  char     ifname[IF_NAMESIZE];
  int      up;
  int      down;
  enum unit up_unit, down_unit;

  /* Previous-cycle snapshots, keyed by interface name */
  struct ifsnap prev[MAX_IFACES];
  int           nprev;

  /* Timing */
  struct timeval tv_nm1, tv_n, tv_delta;
};

/* BSD interface names to skip unconditionally (loopback, Apple internal) */
static const char *const SKIP_PREFIXES[] = {
  "lo", "awdl", "llw", "gif", "stf", "anpi", "ap", "dummy",
  "bridge", "pktap", "ipsec", NULL
};

static inline int should_skip(const char *name) {
  for (int i = 0; SKIP_PREFIXES[i]; i++) {
    size_t plen = strlen(SKIP_PREFIXES[i]);
    if (strncmp(name, SKIP_PREFIXES[i], plen) == 0) return 1;
  }
  return 0;
}

/* Detect the current default-route interface via routing table */
static inline int get_default_interface(char *ifname, size_t len) {
  FILE *fp = popen("route -n get default 2>/dev/null "
                   "| awk '/interface:/ {print $2}'", "r");
  if (!fp) return -1;
  if (fgets(ifname, len, fp) == NULL) {
    pclose(fp);
    return -1;
  }
  pclose(fp);
  char *nl = strchr(ifname, '\n');
  if (nl) *nl = '\0';
  return (strlen(ifname) > 0) ? 0 : -1;
}

/* Read IFMIB data for a given 1-based row; returns 0 on success */
static inline int ifdata_row(uint32_t row, struct ifmibdata *data) {
  size_t sz = sizeof(struct ifmibdata);
  int opt[] = {
    CTL_NET, PF_LINK, NETLINK_GENERIC, IFMIB_IFDATA, (int)row, IFDATA_GENERAL
  };
  return sysctl(opt, 6, data, &sz, NULL, 0);
}

/* Format a byte-rate into (value, unit) */
static inline void format_rate(double rate, int *out_val, enum unit *out_unit) {
  double exp = (rate > 1.0) ? log10(rate) : 0.0;
  if (exp < 3) {
    *out_unit = UNIT_BPS;
    *out_val  = (int)rate;
  } else if (exp < 6) {
    *out_unit = UNIT_KBPS;
    *out_val  = (int)(rate / 1000.0);
  } else {
    *out_unit = UNIT_MBPS;
    *out_val  = (int)(rate / 1000000.0);
  }
}

/*
 * Sample all interfaces, compute per-interface byte-rates, pick the most
 * active one (hybrid: busiest under load, default-route interface at idle).
 *
 * Idle threshold: combined throughput < 1 KBps → fall back to default route.
 *
 * After returning:
 *   net->ifname   — chosen interface name
 *   net->up/down  — upload/download rate for that interface
 *   net->up_unit / net->down_unit — units
 */
static inline void network_sample(struct network *net) {
  /* Advance time */
  gettimeofday(&net->tv_n, NULL);
  timersub(&net->tv_n, &net->tv_nm1, &net->tv_delta);
  net->tv_nm1 = net->tv_n;

  double dt = (double)net->tv_delta.tv_sec
              + 1e-6 * (double)net->tv_delta.tv_usec;
  if (dt < 1e-6 || dt > 1e2) return; /* sanity: skip first tick or stale */

  /* How many interfaces does the kernel know about? */
  int count_opt[] = {
    CTL_NET, PF_LINK, NETLINK_GENERIC, IFMIB_SYSTEM, IFMIB_IFCOUNT
  };
  uint32_t ifcount = 0;
  size_t sz = sizeof(ifcount);
  if (sysctl(count_opt, 5, &ifcount, &sz, NULL, 0) != 0 || ifcount == 0) return;

  /* Mark all previous snapshots as "not yet seen this cycle" */
  for (int i = 0; i < net->nprev; i++) net->prev[i].valid = 0;

  double best_rate = 0.0;
  char   best_name[IF_NAMESIZE] = "";
  double best_din  = 0.0, best_dout = 0.0;

  /* IFMIB rows are 1-based, range [1..ifcount] */
  for (uint32_t row = 1; row <= ifcount; row++) {
    struct ifmibdata d;
    if (ifdata_row(row, &d) != 0) continue;
    if (should_skip(d.ifmd_name))  continue;
    if (d.ifmd_data.ifi_ibytes == 0 && d.ifmd_data.ifi_obytes == 0) continue;

    uint64_t cur_i = d.ifmd_data.ifi_ibytes;
    uint64_t cur_o = d.ifmd_data.ifi_obytes;

    /* Find matching previous snapshot */
    int slot = -1;
    for (int j = 0; j < net->nprev; j++) {
      if (strcmp(net->prev[j].name, d.ifmd_name) == 0) { slot = j; break; }
    }

    if (slot == -1) {
      /* New interface — record snapshot, nothing to compare yet */
      if (net->nprev < MAX_IFACES) {
        slot = net->nprev++;
        strncpy(net->prev[slot].name, d.ifmd_name, IF_NAMESIZE - 1);
        net->prev[slot].name[IF_NAMESIZE - 1] = '\0';
      }
      net->prev[slot].ibytes = cur_i;
      net->prev[slot].obytes = cur_o;
      net->prev[slot].valid  = 1;
      continue;
    }

    uint64_t prev_i = net->prev[slot].ibytes;
    uint64_t prev_o = net->prev[slot].obytes;

    /* Update snapshot */
    net->prev[slot].ibytes = cur_i;
    net->prev[slot].obytes = cur_o;
    net->prev[slot].valid  = 1;

    /* Wrap protection: skip if counter went backwards */
    if (cur_i < prev_i || cur_o < prev_o) continue;

    double din  = (double)(cur_i - prev_i) / dt;
    double dout = (double)(cur_o - prev_o) / dt;

    if ((din + dout) > best_rate) {
      best_rate = din + dout;
      best_din  = din;
      best_dout = dout;
      strncpy(best_name, d.ifmd_name, IF_NAMESIZE - 1);
      best_name[IF_NAMESIZE - 1] = '\0';
    }
  }

  /* Idle threshold: < 1024 B/s total → fall back to default-route interface */
  const double IDLE_THRESHOLD = 1024.0;
  if (best_rate < IDLE_THRESHOLD) {
    char def_if[IF_NAMESIZE] = "";
    if (get_default_interface(def_if, sizeof(def_if)) == 0) {
      strncpy(net->ifname, def_if, IF_NAMESIZE - 1);
    } else if (best_name[0] != '\0') {
      strncpy(net->ifname, best_name, IF_NAMESIZE - 1);
    } else {
      net->ifname[0] = '\0';
    }
    /* Report as zero at idle so the widget dims the values */
    net->up   = 0; net->up_unit   = UNIT_BPS;
    net->down = 0; net->down_unit = UNIT_BPS;
    return;
  }

  strncpy(net->ifname, best_name, IF_NAMESIZE - 1);
  net->ifname[IF_NAMESIZE - 1] = '\0';
  format_rate(best_dout, &net->up,   &net->up_unit);
  format_rate(best_din,  &net->down, &net->down_unit);
}
