#!/usr/bin/env python3
import sys
import os
import re
import time
import subprocess
import shutil

WORKSPACE_DIR = os.path.dirname(os.path.abspath(__file__))
LOG_FILE = os.path.join(WORKSPACE_DIR, "build.log")
ERROR_LOG_FILE = os.path.join(WORKSPACE_DIR, "build_last_error.log")
SYMLINK_PATH = "/Users/a123/.gemini/antigravity/scratch/Scopegram.app"
DERIVED_DATA_APP = "/Users/a123/Library/Developer/Xcode/DerivedData/Telegram-Mac-cxxtmrdbuiplylgbblwrshrmlrkz/Build/Products/Debug/Telegram.app"

# ANSI Colors
BOLD = "\033[1m"
RESET = "\033[0m"
GREEN = "\033[32m"
CYAN = "\033[36m"
YELLOW = "\033[33m"
RED = "\033[31m"
DIM = "\033[2m"

def format_duration(seconds):
    m = int(seconds // 60)
    s = int(seconds % 60)
    return f"{m:02d}:{s:02d}"

def truncate_text(text, max_len=60):
    if len(text) <= max_len:
        return text
    return text[:max_len-3] + "..."

def main():
    auto_run = "--run" in sys.argv
    clean_first = "--clean" in sys.argv

    os.chdir(WORKSPACE_DIR)

    print(f"{BOLD}{CYAN}=== SCOPEGRAM NATIVE BUILDER ==={RESET}")
    print(f"{DIM}Workspace: {WORKSPACE_DIR}{RESET}")
    print(f"{DIM}Full Log:  {LOG_FILE}{RESET}")

    if clean_first:
        print(f"{YELLOW}Cleaning build products...{RESET}")
        subprocess.run(["xcodebuild", "-workspace", "Telegram-Mac.xcworkspace", "-scheme", "Telegram", "clean"],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    cmd = [
        "xcodebuild",
        "-workspace", "Telegram-Mac.xcworkspace",
        "-scheme", "Telegram",
        "-configuration", "Debug",
        "-destination", "platform=macOS,arch=arm64",
        "build",
        "CODE_SIGN_IDENTITY=",
        "CODE_SIGNING_REQUIRED=NO",
        "CODE_SIGNING_ALLOWED=NO"
    ]

    print(f"{CYAN}Compiling Scopegram...{RESET}\n")
    start_time = time.time()

    log_fp = open(LOG_FILE, "w", buffering=1, encoding="utf-8", errors="replace")

    proc = subprocess.Popen(
        cmd,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        bufsize=1,
        universal_newlines=True
    )

    targets_seen = set()
    current_target = "Package Graph"
    current_action = "Resolving dependencies..."
    error_lines = []
    actions_count = 0
    last_ui_update = 0
    last_logged_target = ""

    target_re = re.compile(r"in target '([^']+)'")
    swift_compile_re = re.compile(r"SwiftCompile normal arm64 (.+?\.swift)")
    compile_c_re = re.compile(r"CompileC .+? /(.+?\.(cpp|c|m|mm))")
    link_re = re.compile(r"Ld (.+?) normal arm64")
    module_re = re.compile(r"SwiftEmitModule normal arm64 Emitting\\ module\\ for\\ ([^\s]+)")

    is_interactive = sys.stdout.isatty() and os.environ.get("TERM", "") != "dumb"

    try:
        for line in proc.stdout:
            log_fp.write(line)
            log_fp.flush()
            actions_count += 1

            # Extract target
            t_match = target_re.search(line)
            if t_match:
                t_name = t_match.group(1)
                targets_seen.add(t_name)
                current_target = t_name

            # Extract actions
            s_match = swift_compile_re.search(line)
            if s_match:
                fname = os.path.basename(s_match.group(1))
                current_action = f"Swift: {fname}"
            else:
                c_match = compile_c_re.search(line)
                if c_match:
                    fname = os.path.basename(c_match.group(1))
                    current_action = f"C++: {fname}"
                elif "SwiftDriver" in line:
                    current_action = "Swift Driver"
                elif "Ld " in line:
                    l_match = link_re.search(line)
                    fname = os.path.basename(l_match.group(1)) if l_match else "binary"
                    current_action = f"Linking: {fname}"
                elif "SwiftEmitModule" in line:
                    m_match = module_re.search(line)
                    mod_name = m_match.group(1) if m_match else current_target
                    current_action = f"Module: {mod_name}"

            if "error:" in line.lower() and not line.strip().startswith("//"):
                error_lines.append(line.strip())

            now = time.time()
            if is_interactive:
                if now - last_ui_update >= 0.1:
                    last_ui_update = now
                    elapsed = format_duration(now - start_time)
                    t_count = len(targets_seen)
                    status = f"\r{BOLD}[{elapsed}]{RESET} {CYAN}[{t_count:>3} pkgs]{RESET} {YELLOW}{truncate_text(current_target, 20):<20}{RESET} ➜ {truncate_text(current_action, 36)}"
                    sys.stdout.write(f"\033[K{status}")
                    sys.stdout.flush()
            else:
                # Log on target changes or every 3 seconds
                if (current_target != last_logged_target and len(targets_seen) > 0) or (now - last_ui_update >= 3.0):
                    last_ui_update = now
                    last_logged_target = current_target
                    elapsed = format_duration(now - start_time)
                    t_count = len(targets_seen)
                    print(f"[{elapsed}] [{t_count:>3} pkgs] [{current_target}] {current_action}")

        proc.wait()
    finally:
        log_fp.close()

    total_time = time.time() - start_time

    if is_interactive:
        sys.stdout.write("\033[K\r")
        sys.stdout.flush()

    if proc.returncode == 0:
        print(f"\n{BOLD}{GREEN}✓ COMPILATION SUCCEEDED in {format_duration(total_time)} ({total_time:.1f}s){RESET}")
        
        # Code signing
        print(f"{CYAN}Signing bundle ad-hoc with codesign...{RESET}")
        sign_res = subprocess.run(["codesign", "--force", "--deep", "-s", "-", DERIVED_DATA_APP],
                                  capture_output=True, text=True)
        if sign_res.returncode == 0:
            print(f"{GREEN}✓ Codesign verified.{RESET}")
        else:
            print(f"{YELLOW}Warning: codesign returned {sign_res.returncode}: {sign_res.stderr.strip()}{RESET}")

        # Symlink
        if os.path.exists(DERIVED_DATA_APP):
            try:
                if os.path.islink(SYMLINK_PATH) or os.path.exists(SYMLINK_PATH):
                    os.remove(SYMLINK_PATH)
                os.symlink(DERIVED_DATA_APP, SYMLINK_PATH)
                print(f"{GREEN}✓ Symlinked to: {SYMLINK_PATH}{RESET}")
            except Exception as e:
                print(f"{YELLOW}Symlink error: {e}{RESET}")

        print(f"\n{BOLD}===================================================={RESET}")
        print(f"{BOLD}{GREEN}🎉 SCOPEGRAM IS READY!{RESET}")
        print(f"   Bundle: {BOLD}{SYMLINK_PATH}{RESET}")
        print(f"   Target: {DERIVED_DATA_APP}")
        print(f"   Time:   {total_time:.1f}s")
        print(f"   Log:    {LOG_FILE}")
        print(f"{BOLD}===================================================={RESET}\n")

        if auto_run:
            print(f"{CYAN}Launching Scopegram...{RESET}")
            subprocess.run(["open", SYMLINK_PATH])
        else:
            print(f"To launch: {CYAN}open {SYMLINK_PATH}{RESET}\n")

        return 0
    else:
        print(f"\n{BOLD}{RED}✗ BUILD FAILED (exit code {proc.returncode}) in {format_duration(total_time)}{RESET}")
        print(f"Full log: {BOLD}{LOG_FILE}{RESET}")
        
        if error_lines:
            print(f"\n{BOLD}{RED}Errors detected:{RESET}")
            with open(ERROR_LOG_FILE, "w", encoding="utf-8") as ef:
                for err in error_lines[:25]:
                    print(f"  {RED}• {err}{RESET}")
                    ef.write(err + "\n")
            print(f"\nSaved {len(error_lines)} errors to {ERROR_LOG_FILE}")
        return proc.returncode

if __name__ == "__main__":
    sys.exit(main())
