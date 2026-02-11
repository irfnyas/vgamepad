import socket
import threading
import time
import subprocess
from datetime import datetime

# Try to import pynput, but handle gracefully if it fails
try:
    from pynput.keyboard import Controller, Key
    PYNPUT_AVAILABLE = True
except Exception as e:
    PYNPUT_AVAILABLE = False
    PYNPUT_ERROR = str(e)
    # Dummy classes for when pynput is not available
    class Controller:
        def press(self, key): pass
        def release(self, key): pass
    class Key:
        space = 'space'
        shift = 'shift'
        ctrl = 'ctrl'
        alt = 'alt'
        cmd = 'cmd'
        enter = 'enter'
        esc = 'esc'
        tab = 'tab'
        backspace = 'backspace'
        caps_lock = 'caps_lock'
        up = 'up'
        down = 'down'
        left = 'left'
        right = 'right'

# --- Server Logic ---
UDP_PORT = 5005

def get_local_ip():
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        local_ip = s.getsockname()[0]
        s.close()
        return local_ip
    except Exception:
        return "127.0.0.1"

def setup_adb_reverse(port, log_callback=None):
    """Attempt to setup adb reverse for Android emulators"""
    try:
        # Try to run 'adb reverse tcp:PORT tcp:PORT'
        # This allows the emulator to connect to 127.0.0.1:PORT on the host
        result = subprocess.run(
            ["adb", "reverse", f"tcp:{port}", f"tcp:{port}"],
            capture_output=True, text=True, timeout=2
        )
        if result.returncode == 0:
            if log_callback:
                log_callback(f"✅ ADB Reverse: 127.0.0.1 on emulator is now linked to your PC")
            return True
        return False
    except Exception:
        return False

class VMCServer:
    def __init__(self, log_callback=None):
        self.active_keys = {}
        self.running = False
        self._raw_log_callback = log_callback or (lambda msg: print(f"[*] {msg}"))
        self.sock = None
        self.keyboard = None
        self._keyboard_init_done = False
        # Removed manual repeat logic to allow steady holding in games
        
        # Initialize keyboard controller on macOS main thread
        if not PYNPUT_AVAILABLE:
            self.log_callback(f"⚠️ WARNING: pynput not available - keyboard input will not work!")
            self.log_callback(f"⚠️ Error: {PYNPUT_ERROR}")
            self.keyboard = type('DummyController', (), {'press': lambda self, k: None, 'release': lambda self, k: None})()
            self._keyboard_init_done = True
        else:
            # We need to initialize Controller on the main thread for macOS
            # Use a simple approach: try to init, if it fails, create dummy
            try:
                import threading
                import time
                
                def init_on_main_thread():
                    try:
                        self.keyboard = Controller()
                        self.log_callback("✅ Keyboard controller initialized")
                    except Exception as e:
                        self.log_callback(f"⚠️ Failed to initialize keyboard: {e}")
                        self.keyboard = type('DummyController', (), {'press': lambda self, k: None, 'release': lambda self, k: None})()
                    finally:
                        self._keyboard_init_done = True
                
                # Try to use PyObjC to run on main thread
                try:
                    from Foundation import NSObject, NSThread
                    from PyObjCTools import AppHelper
                    
                    class MainThreadInitializer(NSObject):
                        def initController(self):
                            init_on_main_thread()
                    
                    initializer = MainThreadInitializer.alloc().init()
                    initializer.performSelectorOnMainThread_withObject_waitUntilDone_(
                        'initController', None, True
                    )
                except Exception as e:
                    # PyObjC not available or failed, try direct init
                    self.log_callback(f"⚠️ PyObjC dispatch failed: {e}, trying direct init...")
                    init_on_main_thread()
                
                # Wait for initialization to complete
                timeout = 5.0
                start = time.time()
                while not self._keyboard_init_done and (time.time() - start) < timeout:
                    time.sleep(0.01)
                
                if not self._keyboard_init_done:
                    self.log_callback(f"⚠️ Keyboard initialization timeout")
                    self.keyboard = type('DummyController', (), {'press': lambda self, k: None, 'release': lambda self, k: None})()
                    
            except Exception as e:
                self.log_callback(f"⚠️ Failed to initialize keyboard controller: {e}")
                self.keyboard = type('DummyController', (), {'press': lambda self, k: None, 'release': lambda self, k: None})()
                self._keyboard_init_done = True
    
    def log_callback(self, msg):
        """Pass message to the raw callback without adding another timestamp"""
        self._raw_log_callback(msg)
    
    

    def get_key_object(self, name):
        name = name.lower().strip()
        special_map = {
            'space': Key.space, 'shift': Key.shift, 'ctrl': Key.ctrl, 
            'alt': Key.alt, 'cmd': Key.cmd, 'enter': Key.enter, 
            'esc': Key.esc, 'tab': Key.tab, 'backspace': Key.backspace,
            'caps': Key.caps_lock,
            'up': Key.up, 'down': Key.down, 'left': Key.left, 'right': Key.right,
            '`': '`', '-': '-', '=': '=', '[': '[', ']': ']', '\\': '\\', ';': ';', "'": "'"
        }
        if name in special_map: return special_map[name]
        if name.startswith('f') and name[1:].isdigit():
            return getattr(Key, f'f{name[1:]}', name)
        return name

    def start(self, port=UDP_PORT):
        self.running = True
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        try:
            self.sock.bind(("0.0.0.0", port))
        except Exception as e:
            self.log_callback(f"❌ Failed to bind to port {port}: {e}")
            return

        self.sock.settimeout(1.0) # Allow checking self.running
        
        self.log_callback(f"🚀 Server listening on port {port}")
        self.log_callback(f"📍 Local IP: {get_local_ip()}")
        self.log_callback(f"📱 Android Emulator: Connect to 10.0.2.2:{port}")
        
        # Best effort: Setup ADB reverse for easier connectivity
        setup_adb_reverse(port, self.log_callback)
        connected_clients = set()
        
        while self.running:
            try:
                data, addr = self.sock.recvfrom(1024)
                if addr[0] not in connected_clients:
                    connected_clients.add(addr[0])
                    self.log_callback(f"📱 New client connected: {addr[0]}")
                
                msg = data.decode('utf-8')
                
                if msg == "DISCOVER_VMC_REQUEST":
                    self.sock.sendto(b"DISCOVER_VMC_RESPONSE", addr)
                    continue
                if msg == "ping":
                    self.sock.sendto(b"pong", addr)
                    continue

                for p in msg.split('|'):
                    if not p or ':' not in p: continue
                    key_str, val = p.split(':')
                    try:
                        is_pressed = float(val) > 0.5
                        key_obj = self.get_key_object(key_str)

                        if is_pressed:
                            # Only process if this is a new press (not already pressed)
                            if key_str not in self.active_keys:
                                # Initial press
                                self.keyboard.press(key_obj)
                                self.active_keys[key_str] = key_obj
                                self.log_callback(f"⬇️  {key_str}")
                            
                        elif not is_pressed and key_str in self.active_keys:
                            # Final release
                            self.keyboard.release(self.active_keys[key_str])
                            del self.active_keys[key_str]
                            self.log_callback(f"⬆️  {key_str}")
                    except Exception as e:
                        self.log_callback(f"⚠️ Error parsing message part '{p}': {e}")
                
            except socket.timeout:
                continue
            except Exception as e:
                self.log_callback(f"❌ Error: {str(e)}")

    def stop(self):
        self.running = False
        
        self.active_keys.clear()
        
        if self.sock:
            self.sock.close()
        # Release all keys (only if keyboard was initialized)
        if self.keyboard:
            for obj in self.active_keys.values():
                try: self.keyboard.release(obj)
                except: pass
        self.active_keys.clear()
        self.log_callback("🛑 Server stopped")

if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(description="vGamepad VMC Server")
    parser.add_argument("--port", type=int, default=UDP_PORT, help=f"UDP port to listen on (default: {UDP_PORT})")
    args = parser.parse_args()

    server = VMCServer()
    try:
        server.start(port=args.port)
    except KeyboardInterrupt:
        server.stop()
        print("\n👋 Server shut down.")
