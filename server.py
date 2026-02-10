import socket
from pynput.keyboard import Controller, Key

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

keyboard = Controller()
local_ip = get_local_ip()
active_keys = {} 

sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sock.bind(("0.0.0.0", UDP_PORT))

def get_key_object(name):
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

print("===============================================")
print("     VMC MACBOOK BRIDGE SERVER (PURE)          ")
print("===============================================")
print(f"📍 SERVER IP : {local_ip}")
print(f"🔌 PORT      : {UDP_PORT}")
print("-----------------------------------------------")

try:
    while True:
        data, addr = sock.recvfrom(1024)
        msg = data.decode('utf-8')
        
        if msg == "DISCOVER_VMC_REQUEST":
            sock.sendto(b"DISCOVER_VMC_RESPONSE", addr)
            continue
        if msg == "ping":
            sock.sendto(b"pong", addr)
            continue

        try:
            for p in msg.split('|'):
                if not p or ':' not in p: continue
                key_str, val = p.split(':')
                is_pressed = float(val) > 0.5
                key_obj = get_key_object(key_str)

                if is_pressed and key_str not in active_keys:
                    keyboard.press(key_obj)
                    active_keys[key_str] = key_obj
                elif not is_pressed and key_str in active_keys:
                    keyboard.release(active_keys[key_str])
                    del active_keys[key_str]
            print(f"📡 From {addr[0]} | Active: {list(active_keys.keys())}          ", end='\r')
        except: pass

except KeyboardInterrupt:
    print("\n🛑 Closing...")
finally:
    for obj in active_keys.values():
        try: keyboard.release(obj)
        except: pass
    sock.close()