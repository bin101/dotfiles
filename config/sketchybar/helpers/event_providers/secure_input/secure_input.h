#pragma once

#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <libproc.h>
#include <Carbon/Carbon.h>
#include <ApplicationServices/ApplicationServices.h>

#define MAX_PROCESSES 32
#define MAX_NAME_LENGTH 256

struct secure_process {
  pid_t pid;
  char name[MAX_NAME_LENGTH];
};

struct secure_input_monitor {
  bool is_enabled;
  int process_count;
  struct secure_process processes[MAX_PROCESSES];
};

static inline void secure_input_init(struct secure_input_monitor* monitor) {
    monitor->is_enabled = false;
    monitor->process_count = 0;
    memset(monitor->processes, 0, sizeof(monitor->processes));
}

static inline bool get_process_name_from_pid(pid_t pid, char* name, size_t max_len) {
    if (pid <= 0) {
        strncpy(name, "Unknown", max_len - 1);
        name[max_len - 1] = '\0';
        return false;
    }
    
    // Try to get process name using proc_name
    char temp_name[PROC_PIDPATHINFO_MAXSIZE];
    int ret = proc_name(pid, temp_name, sizeof(temp_name));
    
    if (ret > 0) {
        strncpy(name, temp_name, max_len - 1);
        name[max_len - 1] = '\0';
        return true;
    }
    
    // Fallback: try to get process info using proc_pidinfo
    struct proc_bsdinfo proc_info;
    ret = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &proc_info, sizeof(proc_info));
    
    if (ret == sizeof(proc_info)) {
        strncpy(name, proc_info.pbi_name, max_len - 1);
        name[max_len - 1] = '\0';
        return true;
    }
    
    // Last resort: use "Unknown"
    strncpy(name, "Unknown", max_len - 1);
    name[max_len - 1] = '\0';
    return false;
}

static inline void secure_input_update(struct secure_input_monitor* monitor) {
    // Reset the monitor
    monitor->is_enabled = false;
    monitor->process_count = 0;
    memset(monitor->processes, 0, sizeof(monitor->processes));
    
    // Check if secure input is enabled
    monitor->is_enabled = IsSecureEventInputEnabled();
    
    if (!monitor->is_enabled) {
        return;
    }
    
    // Get list of all running processes
    int num_pids = proc_listallpids(NULL, 0);
    if (num_pids <= 0) {
        // If we can't get process list but secure input is enabled, add generic entry
        monitor->processes[0].pid = -1;
        strncpy(monitor->processes[0].name, "Unknown Process", MAX_NAME_LENGTH - 1);
        monitor->processes[0].name[MAX_NAME_LENGTH - 1] = '\0';
        monitor->process_count = 1;
        return;
    }
    
    pid_t* pid_list = (pid_t*)malloc(num_pids * sizeof(pid_t));
    if (!pid_list) {
        monitor->processes[0].pid = -1;
        strncpy(monitor->processes[0].name, "Unknown Process", MAX_NAME_LENGTH - 1);
        monitor->processes[0].name[MAX_NAME_LENGTH - 1] = '\0';
        monitor->process_count = 1;
        return;
    }
    
    int actual_pids = proc_listallpids(pid_list, num_pids * sizeof(pid_t));
    if (actual_pids <= 0) {
        free(pid_list);
        monitor->processes[0].pid = -1;
        strncpy(monitor->processes[0].name, "Unknown Process", MAX_NAME_LENGTH - 1);
        monitor->processes[0].name[MAX_NAME_LENGTH - 1] = '\0';
        monitor->process_count = 1;
        return;
    }
    
    // Check each process to see if it might be using secure input
    // This is a heuristic approach - we look for common applications that use secure input
    for (int i = 0; i < actual_pids && monitor->process_count < MAX_PROCESSES; i++) {
        pid_t pid = pid_list[i];
        
        if (pid <= 0) continue;
        
        // Get process information
        struct proc_bsdinfo proc_info;
        int ret = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &proc_info, sizeof(proc_info));
        
        if (ret != sizeof(proc_info)) {
            continue;
        }
        
        // Skip kernel processes and system processes (except for some specific ones)
        if (proc_info.pbi_uid == 0) {
            continue;
        }
        
        // Get process path for additional checking
        char proc_path[PROC_PIDPATHINFO_MAXSIZE];
        ret = proc_pidpath(pid, proc_path, sizeof(proc_path));
        
        // Check if this process is likely to use secure input
        bool likely_secure_input = false;
        
        if (ret > 0) {
            // Check common applications that use secure input
            if (strstr(proc_path, "/Applications/") || strstr(proc_path, ".app/")) {
                // Common apps that might use secure input
                if (strstr(proc_info.pbi_name, "1Password") ||
                    strstr(proc_info.pbi_name, "KeyShade") ||
                    strstr(proc_info.pbi_name, "Bitwarden") ||
                    strstr(proc_info.pbi_name, "LastPass") ||
                    strstr(proc_info.pbi_name, "KeePassX") ||
                    strstr(proc_info.pbi_name, "Terminal") ||
                    strstr(proc_info.pbi_name, "iTerm") ||
                    strstr(proc_info.pbi_name, "ssh") ||
                    strstr(proc_info.pbi_name, "sudo")) {
                    likely_secure_input = true;
                }
            }
        }
        
        // Also check just the process name without path
        if (!likely_secure_input) {
            if (strstr(proc_info.pbi_name, "1Password") ||
                strstr(proc_info.pbi_name, "KeyShade") ||
                strstr(proc_info.pbi_name, "Bitwarden") ||
                strstr(proc_info.pbi_name, "Terminal") ||
                strstr(proc_info.pbi_name, "iTerm")) {
                likely_secure_input = true;
            }
        }
        
        if (likely_secure_input) {
            // Add this process to our list
            monitor->processes[monitor->process_count].pid = pid;
            get_process_name_from_pid(pid, 
                monitor->processes[monitor->process_count].name, 
                MAX_NAME_LENGTH);
            monitor->process_count++;
        }
    }
    
    free(pid_list);
    
    // If we found no specific processes but secure input is enabled,
    // add a generic entry
    if (monitor->process_count == 0 && monitor->is_enabled) {
        monitor->processes[0].pid = -1;
        strncpy(monitor->processes[0].name, "Unknown Process", MAX_NAME_LENGTH - 1);
        monitor->processes[0].name[MAX_NAME_LENGTH - 1] = '\0';
        monitor->process_count = 1;
    }
}