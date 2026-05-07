#!/usr/bin/env bash

resolve_demo_root() {
  local script_dir="${1:?missing script directory}"
  local default_root override root

  default_root="$(cd "$script_dir/.." && pwd)"
  override="${NEMOCLAW_PST_DEMO_ROOT:-}"

  if [ -n "$override" ]; then
    root="$(cd "$override" 2>/dev/null && pwd || printf '%s' "$override")"
    if [ -f "$root/scripts/start-demo.sh" ] && [ -f "$root/skills/pst-mail/SKILL.md" ]; then
      printf '%s\n' "$root"
      return 0
    fi

    echo "Ignoring NEMOCLAW_PST_DEMO_ROOT=$override; it does not look like a valid demo checkout." >&2
  fi

  printf '%s\n' "$default_root"
}
