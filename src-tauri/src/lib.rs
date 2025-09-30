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

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
  tauri::Builder::default()
    .menu(|app| build_app_menu(app))
    .on_menu_event(|app, event| handle_menu_event(app, event))
    .setup(|app| {

        let handle = app.handle();
        let _ = build_tray(&handle)?;
        Ok(())
    })
    .run(tauri::generate_context!())
    .expect("error while running Moti");
}
