# vGamepad 🎮

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![Python](https://img.shields.io/badge/Python-3.10%2B-3776AB?logo=python&logoColor=white)](https://www.python.org)

**vGamepad** is a premium, high-performance mobile-to-PC controller solution designed for gamers who demand precision and style. It bridges the gap between mobile touch sensors and PC inputs, providing a tactical, responsive, and fully customizable gaming experience.

---

## ✨ Key Features

- **⚡ Ultra-Low Latency**: Optimized UDP transport layer with a **60Hz (16ms)** synchronization loop for near-instant response.
- **🎨 Dynamic Layout Editor**: Create, move, and resize every button. Build the perfect interface for your specific game.
- **🌈 Advanced Theming**:
    - **Intelligent Contrast**: Modifier keys automatically styled in Slate Gray (`#2A2A2A`) for better visual hierarchy.
    - **Premium Presets**: Deep, dark-themed color swatches (Midnight Red, Forest Green, Deep Blue) to match modern gaming aesthetics.
    - **Hex Precision**: Full control over key colors via a precise hex code editor.
- **📂 Layout Management**:
    - **Infinite Customization**: Save your creations as new templates with custom icons (emojis), titles, and descriptions.
    - **Metadata System**: Real-time listing of custom layouts stored directly on your device.
- **📡 Seamless Connectivity**:
    - **Auto Search**: Instantly find your PC server on the local network.
    - **Manual IP**: Quick-entry for specific network configurations.
- **🕹️ Analog-to-Digital Precision**: Intelligent thresholding converts smooth gestures into crisp binary keyboard signals.

---

## 🎨 Interface Customization

vGamepad isn't just a controller; it's a sandbox. 

1. **Unlock the Grid**: Tap the lock icon to enter edit mode.
2. **Transform Keys**: Resize or move keys with precision sliders.
3. **Style your Way**: Use the color picker to assign presets or unique hex codes to any button.
4. **Save with Style**: Save your layout with a signature emoji and title. Your custom layouts are neatly organized in the selection sheet.

---

## 🛠️ System Requirements

### Mobile (Client)
- **Platform**: Android / iOS
- **Flutter SDK**: 3.x
- **Connection**: 5GHz Wi-Fi or USB Tethering recommended for minimum jitter.

### PC (Server)
- **Python**: 3.10+
- **Platform**: macOS (Verified) / Windows / Linux
- **Permissions**: **Accessibility permissions** required for keyboard emulation.

---

## 📦 Installation & Setup

### 1. Server Configuration (PC/Mac)

#### Option A: Desktop App (GUI)
This provides a premium GUI with automatic IP detection, status monitoring, and easy port configuration.
1. Install dependencies:
   ```bash
   pip3 install -r bridge/requirements.txt
   ```
2. Run the desktop app:
   ```bash
   python3 bridge/main.py
   ```

#### Option B: Terminal Only (CLI)
Run the lightweight server without a GUI.
1. Install dependencies:
   ```bash
   pip3 install pynput
   ```
2. Run the server:
   ```bash
   python3 bridge/server.py
   ```
   *(Optional: specify a different port)*
   ```bash
   python3 bridge/server.py --port 5005
   ```

#### Option C: Build Standalone App
To create a standalone `.app` (macOS) or `.exe` (Windows):
1. Navigate to the server directory:
   ```bash
   cd bridge
   ```
2. Build with Flet:
   ```bash
   flet build macos  # or 'windows'
   ```
The resulting app will be in the `build/` folder.

### 2. Client Configuration (Flutter)
1. **Connect**: Launch the app and ensure your PC and mobile are on the same network.
2. **Select Discovery**:
    - Tap **AUTO SEARCH** to hunt for the server.
    - Tap **MANUAL IP** if you already have the server's IP.
3. **Enjoy**: Once connected, your inputs will be instantly synchronized to your PC.

---

## 📡 Communication Protocol

The system communicates via a lightweight UDP string protocol sent every 16ms. This allows the server to emulate keyboard presses based on your layout's `action` assignments.

**Packet Structure**: `axisX:{val}|trigA:{val}|trigB:{val}|keys:[list_of_actions]`

---

## ⚠️ Troubleshooting

- **Server Not Found**: Ensure your PC's firewall allows incoming traffic on **UDP Port 5005**.
- **No Keyboard Input (macOS)**: You must grant **Accessibility** permissions to the Terminal application or the Python process.
    - `System Settings > Privacy & Security > Accessibility`.
- **Input Jitter**: If possible, use **USB Tethering** for a wired connection experience.

---

## 📜 License
This project is licensed under the MIT License - see the LICENSE file for details.