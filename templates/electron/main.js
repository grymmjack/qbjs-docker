// QBJS + Electron: a native desktop shell that loads the compiled QBJS web
// bundle (dist/index.html) in Electron's bundled Chromium. No app logic lives
// here -- the game/app is the transpiled program.js. This mirrors the Moebius
// main-process pattern (a BrowserWindow that loads a static page).
const { app, BrowserWindow, Menu } = require("electron");
const path = require("path");

function createWindow() {
  const win = new BrowserWindow({
    width: 800,
    height: 600,
    minWidth: 320,
    minHeight: 240,
    title: "{{APP_NAME}}",
    backgroundColor: "#000000",
    autoHideMenuBar: true,
    webPreferences: {
      // QBJS runs as a plain web app (its VFS is in-memory), so the secure
      // defaults are fine. Flip these on only if your program needs Node APIs.
      contextIsolation: true,
      nodeIntegration: false
    }
  });

  // No app menu -- QBJS apps own the whole window like a game.
  Menu.setApplicationMenu(null);
  win.loadFile(path.join(__dirname, "dist", "index.html"));
}

app.whenReady().then(() => {
  createWindow();
  app.on("activate", () => {
    if (BrowserWindow.getAllWindows().length === 0) createWindow();
  });
});

app.on("window-all-closed", () => {
  if (process.platform !== "darwin") app.quit();
});
