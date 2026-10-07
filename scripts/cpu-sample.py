#!/usr/bin/env python3
"""Measures a process's CPU over a window from cumulative CPU time.

`ps -o %cpu` reports a lifetime average and `top -l` truncates its sample
series, so neither is trustworthy for comparing scenarios. Cumulative CPU
time sampled at two instants gives an exact, reproducible figure.
"""
import subprocess, sys, time

def cpu_seconds(pid):
    out = subprocess.run(["ps", "-o", "time=", "-p", str(pid)],
                         capture_output=True, text=True).stdout.strip()
    if not out:
        return None
    parts = out.split(":")
    parts = [float(p) for p in parts]
    while len(parts) < 3:
        parts.insert(0, 0.0)
    h, m, s = parts
    return h * 3600 + m * 60 + s

pid = int(sys.argv[1])
window = float(sys.argv[2]) if len(sys.argv) > 2 else 2.0
count = int(sys.argv[3]) if len(sys.argv) > 3 else 8

readings = []
for _ in range(count):
    a = cpu_seconds(pid)
    time.sleep(window)
    b = cpu_seconds(pid)
    if a is None or b is None:
        print("process gone"); sys.exit(1)
    readings.append((b - a) / window * 100.0)

readings.sort()
import statistics
print(f"n={len(readings)}")
print(f"  mean   {statistics.fmean(readings):6.2f} %")
print(f"  median {statistics.median(readings):6.2f} %")
print(f"  min    {readings[0]:6.2f} %")
print(f"  max    {readings[-1]:6.2f} %")
