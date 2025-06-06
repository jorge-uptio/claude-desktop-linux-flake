# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is an unofficial Nix flake that enables running Anthropic's Claude Desktop application on Linux by repackaging the Windows version. The project consists of two main components:

1. **patchy-cnb** (in `/patchy-cnb/`): A Rust library that reimplements Windows-only native bindings as stubs
2. **claude-desktop**: A Nix package that extracts the Windows installer and repackages it for Linux

## Key Commands

### Building and Running Claude Desktop

```bash
# One-time run
NIXPKGS_ALLOW_UNFREE=1 nix run github:k3d3/claude-desktop-linux-flake --impure

# Build locally
nix build .#claude-desktop

# Build with FHS environment (for MCP support)
nix build .#claude-desktop-with-fhs
```

### Developing patchy-cnb

```bash
cd patchy-cnb
npm run build         # Build release version
npm run build:debug   # Build debug version
npm test             # Run tests
```

## Architecture

The project works by:

1. Downloading Claude Desktop's Windows installer
2. Extracting the Electron app contents
3. Replacing Windows-specific `claude-native-bindings` with `patchy-cnb` stubs
4. Patching the app to enable title bar on Linux
5. Repackaging as a Linux Electron application
6. Configuring proper desktop integration for GNOME/Wayland

Key files:

- `/pkgs/claude-desktop.nix`: Main Nix package definition with desktop integration
- `/patchy-cnb/src/lib.rs`: Stub implementations of Windows native functions
- `/flake.nix`: Nix flake configuration with FHS wrapper for MCP support

When updating for new Claude Desktop versions, modify the version and hash in `/pkgs/claude-desktop.nix`.

## GNOME Desktop Integration

This flake includes fixes for proper GNOME desktop integration:

### Issues Fixed

- **Dock Icon**: Claude now shows the correct orange sunburst icon instead of a generic gear icon
- **Window Grouping**: Running applications properly group with pinned dock icons
- **Wayland Support**: Proper window class and desktop file association on Wayland
- **FHS Compatibility**: The `claude-desktop-with-fhs` package includes desktop files for MCP server support

### Technical Details

- Desktop file named `Claude.desktop` with `StartupWMClass=Claude` for proper window association
- Icon references use `claude` to match installed PNG files in hicolor theme structure
- FHS wrapper uses `symlinkJoin` to combine desktop integration with MCP environment
- Environment variables set for optimal Wayland/Electron integration

### Testing

The integration has been thoroughly tested on GNOME 48 with Wayland and works reliably across different installation methods (local build, Home Manager, system packages).

## Memories

- The location for my NixOS configuration is at `/home/tom/.nixos`. It's entry point is `/home/tom/.nixos/flake.nix`.
