#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use tauri::{
    AppHandle, Manager, Wry,
    menu::{Menu, MenuItemBuilder, PredefinedMenuItem, Submenu, MenuEvent},
    tray::{ TrayIcon, TrayIconBuilder },
    WebviewUrl, WebviewWindowBuilder,
};

const ID_SHOW: &str = "show";
const ID_PREFS: &str = "prefs";
const ID_QUIT: &str = "quit";

fn open_main(app: &AppHandle<Wry>) {
    if let Some(w) = app.get_webview_window("main") {
        let _ = w.show();
        let _ = w.set_focus();
    }
}

fn open_prefs(app: &AppHandle<Wry>) {
    if app.get_webview_window("settings").is_none() {
        let _ = WebviewWindowBuilder::new(app, "settings", WebviewUrl::App("/settings".into()))
            .title("Preferences - Moti")
            .inner_size(720.0, 520.0)
            .resizable(true)
            .center()
            .build();
    }
    if let Some(w) = app.get_webview_window("settings") {
        let _ = w.show();
        let _ = w.set_focus();
    }
}

fn handle_menu_event(app: &AppHandle<Wry>, event: MenuEvent) {
    match event.id().as_ref() {
        ID_SHOW => open_main(app),
        ID_PREFS => open_prefs(app),
        ID_QUIT => app.exit(0),
        _ => {}
    }
}

fn build_app_menu(app: &AppHandle<Wry>) -> tauri::Result<Menu<Wry>> {
    let prefs = MenuItemBuilder::with_id(ID_PREFS, "Preferences…").build(app)?;
    let quit = MenuItemBuilder::with_id(ID_QUIT, "Quit Moti").build(app)?;
    let sep = PredefinedMenuItem::separator(app)?;
    let app_sub = Submenu::with_items(
        app,
        "Moti",
        true,
        &[
            &prefs,
            &sep,
            &quit,
        ],
    )?;
    Menu::with_items(app, &[ &app_sub ])
}

fn build_tray(app: &AppHandle<Wry>) -> tauri::Result<TrayIcon> {
    let open = MenuItemBuilder::with_id(ID_SHOW,  "Open Moti").build(app)?;
    let prefs = MenuItemBuilder::with_id(ID_PREFS, "Preferences…").build(app)?;
    let quit  = MenuItemBuilder::with_id(ID_QUIT,  "Quit").build(app)?;
    let sep = PredefinedMenuItem::separator(app)?;

    let tray_menu = Menu::with_items(app, &[
        &open,
        &prefs,
        &sep,
        &quit,
    ])?;

    TrayIconBuilder::new()
        .menu(&tray_menu)
        .on_menu_event(|app, event| handle_menu_event(app, event))
        .build(app)
}

/* ===========================
 * Commands (Tauri v2)
 * =========================== */
pub mod cmds {
    use std::{ process::Command, fs, thread, time::Duration };
    use std::sync::atomic::{ AtomicBool, Ordering };

    static BUSY: AtomicBool = AtomicBool::new(false);

    fn has_cgsession() -> bool {
        let path = "/System/Library/CoreServices/Menu Extras/User.menu/Contents/Resources/CGSession";
        fs::metadata(path).is_ok()
    }

    #[tauri::command]
    pub fn lock_screen() -> Result<(), String> {
        if BUSY.swap(true, Ordering::SeqCst) { return Ok(()); }
        struct Reset; impl Drop for Reset { fn drop(&mut self) { BUSY.store(false, Ordering::SeqCst); } }
        let _reset = Reset;

        #[cfg(target_os = "macos")]
        {
            if has_cgsession() {
                let status = Command::new("/System/Library/CoreServices/Menu Extras/User.menu/Contents/Resources/CGSession")
                    .arg("-suspend")
                    .status()
                    .map_err(|e| format!("spawn error: {e}"))?;
                if status.success() { 
                    return Ok(()); 
                } else { 
                    eprintln!("[lock] CGSession not found on this macOS"); 
                    thread::sleep(Duration::from_millis(30));
                }
            } else {
                eprintln!("[lock] CGSesion not found on this macOS -> fallback");
            }

            let script = r#"tell application "System Events" to key code 12 using {control down, command down}"#;
            let out = Command::new("osascript")
                .arg("-e").arg(script)
                .output()
                .map_err(|e| format!("osascript spawn error: {e}"))?;
            if out.status.success() { 
                eprintln!("[lock] osascript OK");
                Ok(()) 
            } else { 
                let stderr = String::from_utf8_lossy(&out.stderr).to_string(); 
                Err(format!("osascript failed: {stderr}\n(Hint: grant Accessibility permission to this app)"))
            }
        }
                
        #[cfg(not(target_os="macos"))]
        { Err("lock_screen not supported on this OS".into()) }
    }

    #[tauri::command]
    pub fn open_accessibility_pane() -> Result<(), String> {
        #[cfg(target_os = "macos")]
        {
            Command::new("open")
                .arg("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
                .status()
                .map_err(|e| format!("open prefs failed: {e}"))?;
            Ok(())
        }
        #[cfg(not(target_os = "macos"))]
        { Err("not supported".into()) }
    }

    #[tauri::command]
    pub fn open_automation_pane() -> Result<(), String> {
        #[cfg(target_os = "macos")]
        {
            Command::new("open")
                .arg("x-apple.systempreferences:com.apple.preference.security")
                .status()
                .map_err(|e| format!("open prefs failed: {e}"))?;
            Ok(())
        }
        #[cfg(not(target_os = "macos"))]
        { Err("not supported".into()) }
    }
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_shell::init())
        .plugin(tauri_plugin_log::Builder::default().build())
        .menu(|app| build_app_menu(app))
        .on_menu_event(|app, event| handle_menu_event(app, event))
        .setup(|app| {

            let handle = app.handle();
            let _ = build_tray(&handle)?;
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            cmds::lock_screen,
            cmds::open_accessibility_pane,
            cmds::open_automation_pane,
        ])
        .run(tauri::generate_context!())
        .expect("error while running Moti");
}
