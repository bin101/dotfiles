/*
 * Secure Input Event Provider for SketchyBar
 * 
 * This program monitors macOS secure input status and reports which processes
 * are potentially using secure input mode.
 * 
 * Usage:
 *   ./bin/secure_input "secure_input_event" "1.0"
 *   
 *   Parameters:
 *     - event-name: Name of the sketchybar event to trigger (e.g., "secure_input_event")
 *     - event_freq: Update frequency in seconds (e.g., "1.0" for 1 second)
 * 
 * Event Variables:
 *   The event will provide the following variables to sketchybar:
 *     - enabled: "true" or "false" - whether secure input is currently enabled
 *     - process_count: Number of processes potentially using secure input
 *     - process_names: Comma-separated list of process names
 *     - process_pids: Comma-separated list of process PIDs
 * 
 * Example SketchyBar Usage:
 *   In your sketchybarrc or items configuration:
 *   
 *   sketchybar --add event secure_input_event \
 *              --add item secure_input right \
 *              --set secure_input \
 *                  icon="🔒" \
 *                  script="$HOME/.config/sketchybar/plugins/secure_input.sh" \
 *              --subscribe secure_input secure_input_event
 *   
 *   Then start the event provider:
 *   $HOME/.config/sketchybar/helpers/event_providers/secure_input/bin/secure_input "secure_input_event" "2.0" &
 */

#include "secure_input.h" 
#include "../sketchybar.h"

int main(int argc, char** argv) {
    float update_freq;
    if (argc < 3 || (sscanf(argv[2], "%f", &update_freq) != 1)) {
        printf("Usage: %s \"<event-name>\" \"<event_freq>\"\n", argv[0]);
        exit(1);
    }

    alarm(0);
    struct secure_input_monitor monitor;
    secure_input_init(&monitor);

    // Setup the event in sketchybar
    char event_message[512];
    snprintf(event_message, 512, "--add event '%s'", argv[1]);
    sketchybar(event_message);

    char trigger_message[2048];
    for (;;) {
        // Acquire new info
        secure_input_update(&monitor);

        // Prepare the event message with secure input status
        if (monitor.is_enabled) {
            char process_list[1024] = "";
            char pid_list[256] = "";
            
            // Build process names string
            for (int i = 0; i < monitor.process_count; i++) {
                if (i > 0) {
                    strncat(process_list, ",", sizeof(process_list) - strlen(process_list) - 1);
                    strncat(pid_list, ",", sizeof(pid_list) - strlen(pid_list) - 1);
                }
                
                strncat(process_list, monitor.processes[i].name, 
                       sizeof(process_list) - strlen(process_list) - 1);
                
                char pid_str[16];
                snprintf(pid_str, sizeof(pid_str), "%d", monitor.processes[i].pid);
                strncat(pid_list, pid_str, sizeof(pid_list) - strlen(pid_list) - 1);
            }
            
            // Trigger the event with secure input data
            snprintf(trigger_message,
                     sizeof(trigger_message),
                     "--trigger '%s' enabled='true' process_count='%d' process_names='%s' process_pids='%s'",
                     argv[1],
                     monitor.process_count,
                     process_list,
                     pid_list);
        } else {
            // Trigger the event indicating secure input is disabled
            snprintf(trigger_message,
                     sizeof(trigger_message),
                     "--trigger '%s' enabled='false' process_count='0' process_names='' process_pids=''",
                     argv[1]);
        }

        // Trigger the event
        sketchybar(trigger_message);

        // Wait
        usleep(update_freq * 1000000);
    }
    
    return 0;
}