# vGamepad Desktop Bridge 🎮

This folder contains the desktop server for vGamepad, which bridges mobile inputs to your PC's keyboard.

## 📁 Structure

- `main.py`: The Flet-based Graphical User Interface (GUI).
- `server.py`: The core VMC Server logic with a functional Command Line Interface (CLI).
- `requirements.txt`: Python package dependencies.

## 🚀 How to Run

### Option 1: Desktop App (GUI)
Provides a visual interface for monitoring connections and logs.
```bash
# From the bridge directory
python3 main.py
```

### Option 2: Terminal Mode (CLI)
A lightweight, non-GUI version that runs directly in your terminal.
```bash
# From the bridge directory
python3 server.py
```
*(Optional: specify a port)*
```bash
python3 server.py --port 5005
```

## 🛠️ Setup & Installation

It is recommended to use a virtual environment to manage dependencies:

```bash
# Create a virtual environment
python3 -m venv .venv

# Activate the virtual environment
# On macOS/Linux:
source .venv/bin/activate
# On Windows:
.venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt
```

## 🏗️ Build

To package the Flet app into a standalone executable (run from the `bridge` directory):

### macOS
```bash
flet build macos
```

### Windows
```bash
flet build windows
```

**Note for macOS users**: You must grant **Accessibility** permissions to your Terminal (or the compiled App) in `System Settings > Privacy & Security > Accessibility` to allow it to emulate keyboard input.
