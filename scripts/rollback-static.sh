#!/bin/sh
set -eu

[ "$(id -u)" -eq 0 ] || { echo "run as root on the VPS" >&2; exit 1; }
[ "$#" -eq 2 ] || { echo "usage: $0 <app-slug> <staging|production>" >&2; exit 2; }
app=$1; env_name=$2
case "$app" in *[!A-Za-z0-9._-]*) echo "unsafe app slug" >&2; exit 2;; esac
case "$env_name" in staging|production) ;; *) echo "invalid environment" >&2; exit 2;; esac
root="/var/www/$app-$env_name"
[ -d "$root" ] && [ -d "$root.previous" ] || { echo "current or previous release missing" >&2; exit 1; }
mv "$root" "$root.failed"
mv "$root.previous" "$root"
mv "$root.failed" "$root.previous"
echo "Rolled back $root. Reload Caddy only if its configuration also changed."
