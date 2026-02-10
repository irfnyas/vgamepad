# vGamepad 🎮

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![Python](https://img.shields.io/badge/Python-3.10%2B-3776AB?logo=python&logoColor=white)](https://www.python.org)

**vGamepad** is a high-performance, low-latency mobile-to-PC controller solution designed specifically for simulation and racing games. It bridges the gap between mobile touch sensors and PC inputs, providing a tactical, responsive driving experience.

---

## ✨ Key Features

-   **⚡ Ultra-Low Latency**: Optimized UDP transport layer with a **60Hz (16ms)** synchronization loop.
-   **🕹️ Analog-to-Digital Precision**: Intelligent thresholding converts smooth analog gestures (rotation/sliders) into crisp binary keyboard signals (`WASD`).
-   **🎛️ Dual-Core Architecture**:
    -   **Mobile App**: A sleek Flutter interface utilizing high-fidelity haptic feedback and real-time sensor polling.
    -   **Python Server**: A lightweight background service for cross-platform keyboard emulation.
-   **📊 Real-time Debug Overlay**: Live diagnostic monitor showing packet throughput, IP status, and raw data payloads.
-   **💓 Haptic Feedback Engine**: Implements physical tactile ticks when controls reach their maximum axes.

---

## 🛠️ System Requirements

### Mobile (Client)
-   **Flutter SDK**: 3.x
-   **Connection**: 5GHz Wi-Fi recommended for minimum jitter.

### PC (Server)
-   **Python**: 3.10+
-   **Architecture**: macOS (Tested) / Windows / Linux
-   **Permissions**: Accessibility permissions required for keyboard simulation (macOS).

---

## 📦 Installation & Setup

### 1. Server Configuration (PC/Mac)
Install the required dependency for keyboard emulation:
```bash
pip3 install pynput
```

Run the server script:
```bash
python3 server.py
```

### 2. Client Configuration (Flutter)
1.  **Find your PC's IP address**:
    ```bash
    # On macOS/Linux
    ipconfig getifaddr en0
    
    # On Windows
    ipconfig
    ```
2.  **Open `lib/main.dart`** and update the `pcIp` variable in the `UdpService` class:
    ```dart
    // line 16
    final String pcIp = "YOUR_PC_IP_HERE"; 
    ```
3.  **Run the app**:
    ```bash
    flutter run --release
    ```

---

## 📡 Communication Protocol

The system communicates via a lightweight UDP string protocol sent every 16ms:

| Segment | Range | Mapping |
| :--- | :--- | :--- |
| `axisX` | `-1.0` to `1.0` | Steering (Left: `A` / Right: `D`) |
| `trigA` | `0.0` to `1.0` | Acceleration (Forward: `W`) |
| `trigB` | `0.0` to `1.0` | Braking (Backward: `S`) |

**Template**: `axisX:{val}|trigA:{val}|trigB:{val}`

---

## ⚠️ Troubleshooting

-   **Connection Failed**: Ensure your PC's firewall allows incoming traffic on **UDP Port 5005**.
-   **No Keyboard Input (macOS)**: You must grant **Accessibility** permissions to the Terminal application or IDE running the server.
    -   Go to `System Settings > Privacy & Security > Accessibility`.
-   **Input Jitter**: Wi-Fi interference can cause packet loss. If possible, use **USB Tethering** for a wired connection experience.

---

## 📜 License
This project is licensed under the MIT License - see the LICENSE file for details.