// QBJS + Tauri: a native desktop shell that loads the compiled QBJS web bundle
// (../dist) in the OS webview. No app logic lives here -- the game/app is the
// transpiled program.js. This keeps the native binary tiny.
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

fn main() {
    tauri::Builder::default()
        .run(tauri::generate_context!())
        .expect("error while running QBJS Tauri application");
}
