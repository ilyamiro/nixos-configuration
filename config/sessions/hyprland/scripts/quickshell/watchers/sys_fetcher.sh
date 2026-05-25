#!/usr/bin/env bash

# 1. Read initial values for time-sensitive metrics (CPU and Network)
read -r _ u1 n1 s1 i1 io1 ir1 so1 st1 g1 gn1 <<< "$(grep '^cpu ' /proc/stat)"
read rx1 tx1 <<< "$(awk -v IGNORECASE=1 '/^ *[ew]/{rx+=$2; tx+=$10} END{print rx, tx}' /proc/net/dev)"

# 2. Small delay to calculate precise usage deltas
sleep 0.5

# 3. Read final values
read -r _ u2 n2 s2 i2 io2 ir2 so2 st2 g2 gn2 <<< "$(grep '^cpu ' /proc/stat)"
read rx2 tx2 <<< "$(awk -v IGNORECASE=1 '/^ *[ew]/{rx+=$2; tx+=$10} END{print rx, tx}' /proc/net/dev)"

# --- CPU Calculation ---
IDLE1=$i1; TOTAL1=$((u1 + n1 + s1 + i1 + io1 + ir1 + so1 + st1))
IDLE2=$i2; TOTAL2=$((u2 + n2 + s2 + i2 + io2 + ir2 + so2 + st2))
DIFF_IDLE=$((IDLE2 - IDLE1))
DIFF_TOTAL=$((TOTAL2 - TOTAL1))
if [ "$DIFF_TOTAL" -eq 0 ]; then CPU_USAGE=0; else CPU_USAGE=$(( 100 * (DIFF_TOTAL - DIFF_IDLE) / DIFF_TOTAL )); fi

# --- Network Calculation ---
# Bytes across 0.5 seconds multiplied by 2 = Bytes per second
RX_RATE=$(((rx2 - rx1) * 2))
TX_RATE=$(((tx2 - tx1) * 2))

# --- RAM Calculation ---
while IFS=":" read -r key val; do
    case "$key" in
        MemTotal) TOTAL_MEM=$(echo "$val" | awk '{print $1}') ;;
        MemAvailable) AVAIL_MEM=$(echo "$val" | awk '{print $1}') ;;
    esac
done < /proc/meminfo
USED_MEM=$((TOTAL_MEM - AVAIL_MEM))
RAM_PCT=$(( 100 * USED_MEM / TOTAL_MEM ))
RAM_GB=$(awk "BEGIN {printf \"%.1f\", $USED_MEM / 1024 / 1024}")

# --- Temperature Calculation ---
TEMP_RAW=""

# Attempt 1: Check hwmon for known CPU temperature drivers (Intel, AMD, ARM)
for hwmon in /sys/class/hwmon/hwmon*; do
    if [ -f "$hwmon/name" ]; then
        hwmon_name=$(cat "$hwmon/name" 2>/dev/null)
        if [[ "$hwmon_name" =~ ^(coretemp|k10temp|zenpower|cpu_thermal|bcm2835_thermal)$ ]]; then
            # Usually temp1_input is the main package/die temp
            if [ -f "$hwmon/temp1_input" ]; then
                TEMP_RAW=$(cat "$hwmon/temp1_input" 2>/dev/null)
                break
            fi
        fi
    fi
done

# Attempt 2: Fallback to thermal_zone for known CPU identifiers
if [ -z "$TEMP_RAW" ]; then
    for tz in /sys/class/thermal/thermal_zone*; do
        if [ -f "$tz/type" ]; then
            tz_type=$(cat "$tz/type" 2>/dev/null)
            if [[ "$tz_type" =~ ^(x86_pkg_temp|cpu_thermal|cpu-thermal)$ ]]; then
                TEMP_RAW=$(cat "$tz/temp" 2>/dev/null)
                break
            fi
        fi
    done
fi

# Attempt 3: Ultimate fallback to the first available hardware monitor or thermal zone
if [ -z "$TEMP_RAW" ]; then
    TEMP_RAW=$(cat /sys/class/hwmon/hwmon0/temp1_input 2>/dev/null || cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null || echo 0)
fi

# Normalize to degrees Celsius
if [ "$TEMP_RAW" -gt 1000 ]; then
    TEMP=$((TEMP_RAW / 1000))
else
    TEMP=$TEMP_RAW
fi

# --- GPU Calculation ---
# Prefer kernel-exposed busy percentages (works well on AMD), then fall back to nvidia-smi.
GPU_USAGE=-1

for busy_file in /sys/class/drm/card[0-9]*/device/gpu_busy_percent; do
    [ -r "$busy_file" ] || continue
    GPU_VAL=$(cat "$busy_file" 2>/dev/null)
    case "$GPU_VAL" in
        ""|*[!0-9]*)
            continue
            ;;
    esac
    if [ "$GPU_USAGE" -lt "$GPU_VAL" ]; then
        GPU_USAGE=$GPU_VAL
    fi
done

if [ "$GPU_USAGE" -lt 0 ] && command -v nvidia-smi >/dev/null 2>&1; then
    NV_GPU=$(nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits 2>/dev/null | awk '
        NF {
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", $1)
            if ($1 + 0 > max || NR == 1) max = $1 + 0
            found = 1
        }
        END {
            if (found) print max
        }
    ')
    if [ -n "$NV_GPU" ]; then
        GPU_USAGE=$NV_GPU
    fi
fi

# --- Output formatted string ---
# Format: CPU|RAM_PCT|RAM_GB|TEMP|RX_RATE|TX_RATE|GPU_USAGE
echo "$CPU_USAGE|$RAM_PCT|$RAM_GB|$TEMP|$RX_RATE|$TX_RATE|$GPU_USAGE"
