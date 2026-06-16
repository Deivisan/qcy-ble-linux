#!/bin/bash
# BrowserOS — mic BT no Linux:
# Wayland + portal KDE lista só wpctl Sources (vazio em A2DP).
# X11 usa Pulse como OpenWhispr (vê bluez_input em A2DP).
export PULSE_SERVER="unix:/run/user/$(id -u)/pulse/native"
export PIPEWIRE_REMOTE="/run/user/$(id -u)/pipewire-0"
APPIMAGE="${HOME}/.local/share/browseros/BrowserOS.AppImage"
if [ ! -f "$APPIMAGE" ]; then
    notify-send "BrowserOS" "AppImage not found at $APPIMAGE" -u critical
    exit 1
fi
exec "$APPIMAGE" --ozone-platform=x11 "$@"