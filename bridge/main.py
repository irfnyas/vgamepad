import flet as ft
import socket
import threading
import time
from server import VMCServer, get_local_ip, UDP_PORT

# --- UI Components ---

def main(page: ft.Page):
    page.title = "vGamepad Bridge"
    page.window.width = 450
    page.window.height = 800
    page.window.resizable = True
    page.bgcolor = "#0F111A"
    page.padding = 20
    page.theme_mode = ft.ThemeMode.DARK

    # --- State ---
    server_instance = None
    local_ip = get_local_ip()
    current_port = UDP_PORT

    # --- UI Refs ---
    log_column = ft.Column(scroll=ft.ScrollMode.ADAPTIVE, expand=True, spacing=5)
    status_text = ft.Text("OFFLINE", color=ft.Colors.RED_400, weight=ft.FontWeight.BOLD)
    status_icon = ft.Icon(ft.Icons.SENSORS, color=ft.Colors.RED_400, size=40)
    ip_display = ft.Text(local_ip, size=32, weight=ft.FontWeight.BOLD, color=ft.Colors.CYAN_400)
    port_text = ft.Text(f"Listening on PORT {current_port}", size=14, color=ft.Colors.CYAN_200)
    
    # --- UI Elements state holders ---
    toggle_text = ft.Text("START SERVER", color=ft.Colors.WHITE)
    toggle_icon = ft.Icon(ft.Icons.PLAY_ARROW_ROUNDED, color=ft.Colors.WHITE)
    
    def log_message(msg):
        timestamp = time.strftime("%H:%M:%S")
        log_column.controls.insert(0,
            ft.Text(f"[{timestamp}] {msg}", size=12, color=ft.Colors.BLUE_GREY_200)
        )
        if len(log_column.controls) > 100:
            log_column.controls.pop()
        page.update()

    def clear_logs(e):
        log_column.controls.clear()
        log_message("🧹 Logs cleared")
        page.update()

    is_running = False
    
    def handle_toggle(e):
        nonlocal server_instance, is_running
        if is_running:
            # STOP
            is_running = False
            toggle_text.value = "START SERVER"
            toggle_icon.name = ft.Icons.PLAY_ARROW_ROUNDED
            toggle_btn.style.bgcolor = ft.Colors.with_opacity(0.1, ft.Colors.GREEN_400)
            
            status_text.value = "OFFLINE"
            status_text.color = ft.Colors.RED_400
            status_icon.color = ft.Colors.RED_400
            
            if server_instance:
                server_instance.stop()
                server_instance = None
            log_message("⏹️ Stop signal sent to server")
        else:
            # START
            try:
                is_running = True
                toggle_text.value = "STOP SERVER"
                toggle_icon.name = ft.Icons.STOP_ROUNDED
                toggle_btn.style.bgcolor = ft.Colors.with_opacity(0.1, ft.Colors.RED_400)
                
                status_text.value = "ONLINE"
                status_text.color = ft.Colors.GREEN_400
                status_icon.color = ft.Colors.GREEN_400
                
                log_message(f"📡 Starting server on port {current_port}...")
                server_instance = VMCServer(log_message)
                threading.Thread(target=server_instance.start, args=(current_port,), daemon=True).start()
            except Exception as e:
                is_running = False
                toggle_text.value = "START SERVER"
                toggle_icon.name = ft.Icons.PLAY_ARROW_ROUNDED
                toggle_btn.style.bgcolor = ft.Colors.with_opacity(0.1, ft.Colors.GREEN_400)
                status_text.value = "OFFLINE"
                log_message(f"❌ Error: {str(e)}")
        
        page.update()

    # --- Settings Dialog ---
    port_input = ft.TextField(
        label="UDP Port", 
        value=str(current_port),
        keyboard_type=ft.KeyboardType.NUMBER,
        border_color=ft.Colors.CYAN_700,
        focused_border_color=ft.Colors.CYAN_400
    )

    def save_port(e):
        nonlocal current_port
        try:
            new_port = int(port_input.value)
            if 1024 <= new_port <= 65535:
                current_port = new_port
                port_text.value = f"Listening on PORT {current_port}"
                log_message(f"⚙️ Port updated to {current_port}")
                settings_dialog.open = False
                page.update()
        except: pass

    settings_dialog = ft.AlertDialog(
        title=ft.Text("Settings"),
        content=port_input,
        actions=[
            ft.TextButton("Cancel", on_click=lambda _: setattr(settings_dialog, 'open', False) or page.update()),
            ft.Button(content=ft.Text("Save"), on_click=save_port, bgcolor=ft.Colors.CYAN_700, color=ft.Colors.WHITE),
        ],
    )
    page.overlay.append(settings_dialog)

    def show_settings(e):
        settings_dialog.open = True
        page.update()

    # --- UI Elements ---
    header = ft.Row(
        [
            ft.Column([
                ft.Text("vGamepad", size=24, weight=ft.FontWeight.BOLD, color=ft.Colors.WHITE),
                ft.Text("Desktop Bridge", size=14, color=ft.Colors.BLUE_GREY_400),
            ]),
            ft.PopupMenuButton(
                items=[
                    ft.PopupMenuItem(content=ft.Text("Change Port"), icon=ft.Icons.SETTINGS, on_click=show_settings),
                    ft.PopupMenuItem(content=ft.Text("Clear Logs"), icon=ft.Icons.DELETE, on_click=clear_logs),
                ],
            )
        ],
        alignment=ft.MainAxisAlignment.SPACE_BETWEEN
    )

    status_card = ft.Container(
        content=ft.Column([
            ft.Row([status_icon, status_text], alignment=ft.MainAxisAlignment.CENTER),
            ft.Divider(height=30, color=ft.Colors.WHITE10),
            ft.Text("LOCAL IP ADDRESS", size=12, color=ft.Colors.BLUE_GREY_400),
            ip_display,
            port_text,
        ], horizontal_alignment=ft.CrossAxisAlignment.CENTER),
        padding=30,
        border_radius=20,
        bgcolor=ft.Colors.with_opacity(0.05, ft.Colors.WHITE),
        border=ft.Border.all(1, ft.Colors.WHITE10),
    )

    toggle_btn = ft.Button(
        content=ft.Row([toggle_icon, toggle_text], alignment=ft.MainAxisAlignment.CENTER),
        width=float("inf"),
        height=55,
        style=ft.ButtonStyle(
            color=ft.Colors.WHITE,
            bgcolor=ft.Colors.with_opacity(0.1, ft.Colors.GREEN_400),
            shape=ft.RoundedRectangleBorder(radius=12),
        ),
        on_click=handle_toggle
    )

    log_box = ft.Column([
        ft.Text("ACTIVITY LOG", size=12, weight=ft.FontWeight.BOLD, color=ft.Colors.BLUE_GREY_400),
        ft.Container(
            content=log_column,
            padding=15,
            bgcolor=ft.Colors.BLACK,
            border_radius=10,
            expand=True,
            width=float("inf"),
        )
    ], expand=True, spacing=10)

    # Wrap in a single expanding Column to fix layout in packaged apps
    page.add(
        ft.Column([
            header,
            status_card,
            toggle_btn,
            log_box
        ], expand=True, spacing=20)
    )

    # Initial logs
    log_message("🎮 vGamepad Bridge initialized")
    log_message(f"📍 My IP: {local_ip}")

if __name__ == "__main__":
    ft.run(main)
