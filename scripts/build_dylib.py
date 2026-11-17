#!/usr/bin/env python3
"""
Build a Dark Agent dylib via the Mythic scripting API.
Copies build parameters from the last .bin build and creates a dylib variant.

Usage:
    pip install mythic
    python3 build_dylib.py [--server-ip IP] [--username USER] [--password PASS]
"""

import asyncio
import argparse
import sys
from mythic import mythic


async def main():
    parser = argparse.ArgumentParser(description="Build Dark Agent dylib via Mythic API")
    parser.add_argument("--server-ip", default="127.0.0.1", help="Mythic server IP")
    parser.add_argument("--server-port", type=int, default=7443, help="Mythic server port")
    parser.add_argument("--username", default="mythic_admin", help="Mythic username")
    parser.add_argument("--password", default="mNmrDrvQIblNabb", help="Mythic password")
    parser.add_argument("--output", default="dark-agent-test.dylib", help="Output filename")
    parser.add_argument("--debug", action="store_true", help="Build in debug mode")
    args = parser.parse_args()

    print(f"[*] Logging into Mythic at {args.server_ip}:{args.server_port}...")
    m = await mythic.login(
        username=args.username,
        password=args.password,
        server_ip=args.server_ip,
        server_port=args.server_port,
        ssl=True,
        global_timeout=-1
    )
    print("[+] Logged in successfully")

    # Get all payloads and find the last Dark Agent .bin build
    print("[*] Fetching existing payloads...")
    payloads = await mythic.get_all_payloads(mythic=m)

    last_bin = None
    for p in payloads:
        pt_name = p.get("payload_type", {}).get("name", "")
        filename = p.get("filemetum", {}).get("filename", "")
        if "dark" in pt_name.lower() and filename.endswith(".bin"):
            last_bin = p
            # Don't break — keep going to find the most recent one

    if not last_bin:
        print("[!] No existing Dark Agent .bin build found.")
        print("[!] You'll need to create a payload from the Mythic UI first, then re-run this script.")
        sys.exit(1)

    pt_name = last_bin["payload_type"]["name"]
    print(f"[+] Found last .bin build: {last_bin['filemetum']['filename']} (payload type: {pt_name})")

    # Extract build parameters and override output_format to dylib
    build_params = last_bin.get("build_parameters", [])
    dylib_params = []
    for param in build_params:
        name = param.get("name", "")
        value = param.get("value")
        if name == "output_format":
            dylib_params.append({"name": "output_format", "value": "dylib"})
        elif name == "debug_mode":
            dylib_params.append({"name": "debug_mode", "value": args.debug})
        else:
            dylib_params.append({"name": name, "value": value})

    # If output_format wasn't in the original params, add it
    if not any(p["name"] == "output_format" for p in dylib_params):
        dylib_params.append({"name": "output_format", "value": "dylib"})

    # Extract C2 profile configuration from the existing payload
    c2_profiles = []
    for c2_info in last_bin.get("c2profileparametersinstances", []):
        profile_name = c2_info.get("c2_profile", {}).get("name", "http")
        profile_params = {}
        for inst in c2_info.get("instances", []):
            profile_params[inst["name"]] = inst["value"]
        c2_profiles.append({
            "c2_profile": profile_name,
            "c2_profile_parameters": profile_params
        })

    if not c2_profiles:
        print("[!] Could not extract C2 profile from last build — using defaults")
        c2_profiles = [{"c2_profile": "http", "c2_profile_parameters": {}}]

    # Extract commands from the existing payload
    commands = [cmd.get("command", {}).get("cmd", "") for cmd in last_bin.get("commands", []) if cmd.get("command", {}).get("cmd")]

    print(f"[*] Building dylib with params: {[p['name'] + '=' + str(p['value']) for p in dylib_params]}")
    print(f"[*] C2 profile: {c2_profiles[0]['c2_profile']}")
    print(f"[*] Commands: {len(commands)} commands")
    print(f"[*] Starting build (this may take a few minutes)...")

    resp = await mythic.create_payload(
        mythic=m,
        payload_type_name=pt_name,
        filename=args.output,
        operating_system="macOS",
        build_parameters=dylib_params,
        c2_profiles=c2_profiles,
        commands=commands,
        return_on_complete=True
    )

    print(f"[*] Build response: {resp}")

    if resp.get("status", "") == "success":
        print(f"[+] Dylib built successfully: {args.output}")
        # Download the payload
        payload_uuid = resp.get("uuid", "")
        if payload_uuid:
            print(f"[+] Payload UUID: {payload_uuid}")
            print(f"[*] Download from Mythic UI or use: mythic.download_payload(mythic=m, payload_uuid='{payload_uuid}')")
    else:
        print(f"[!] Build failed: {resp}")
        sys.exit(1)


if __name__ == "__main__":
    asyncio.run(main())
