const { app, BrowserWindow, Menu, ipcMain } = require('electron');
const { execSync } = require('child_process');

function createWindow() {
    const win = new BrowserWindow({
        width: 800,
        height: 600,
        frame: true,
        autoHideMenuBar: true,
        webPreferences: {
            nodeIntegration: true,
            contextIsolation: false
        }
    });

    Menu.setApplicationMenu(null);

    win.loadFile('src/index.html');
}

app.whenReady().then(createWindow);

app.on('window-all-closed', () => {
    if (process.platform !== 'darwin') app.quit();
});

ipcMain.handle('get-disks', async () => {
    try {
        const output = execSync('lsblk -nd -o NAME,TYPE', { encoding: 'utf-8' });
        const lines = output.trim().split('\n');
        
        const disks = lines
            .filter(line => {
                const [name, type] = line.split(/\s+/);
                return type === 'disk' && !name.startsWith('loop');
            })
            .map(line => {
                const name = line.split(/\s+/)[0];
                return `/dev/${name}`;
            });

        return { success: true, disks };
    } catch (error) {
        return { success: false, error: error.message };
    }
});

ipcMain.on('close-my-tuff-window', () => {
    app.quit();
});