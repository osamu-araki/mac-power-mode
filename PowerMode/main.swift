// Power Mode — メニューバー常駐の電源モード切替アプリ
// Version: 1.1.0 | Updated: 2026-05-09

import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var statusItem: NSStatusItem!

    /// スクリプトの探索順:
    /// 1. 環境変数 POWER_MODE_SCRIPTS_DIR
    /// 2. アプリバンドル内 Contents/Resources/scripts
    /// 3. ~/scripts （後方互換）
    lazy var scriptsBase: String = {
        if let env = ProcessInfo.processInfo.environment["POWER_MODE_SCRIPTS_DIR"], !env.isEmpty {
            return (env as NSString).expandingTildeInPath
        }
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("scripts").path,
           FileManager.default.fileExists(atPath: bundled) {
            return bundled
        }
        return (NSHomeDirectory() as NSString).appendingPathComponent("scripts")
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        let menu = NSMenu()
        menu.delegate = self

        let header = NSMenuItem(title: "状態確認中…", action: nil, keyEquivalent: "")
        header.isEnabled = false
        header.tag = 1
        menu.addItem(header)

        menu.addItem(NSMenuItem.separator())

        let mobileItem = NSMenuItem(title: "Mobile Mode に切替", action: #selector(switchToMobile), keyEquivalent: "m")
        mobileItem.target = self
        menu.addItem(mobileItem)

        let normalItem = NSMenuItem(title: "Normal Mode に切替", action: #selector(switchToNormal), keyEquivalent: "n")
        normalItem.target = self
        menu.addItem(normalItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "終了", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        updateStatus()
    }

    @objc func switchToMobile() {
        runScript("\(scriptsBase)/mobile-mode.sh")
        updateStatus()
    }

    @objc func switchToNormal() {
        runScript("\(scriptsBase)/normal-mode.sh")
        updateStatus()
    }

    @objc func quitApp() {
        NSApp.terminate(nil)
    }

    func runScript(_ path: String) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/bash")
        task.arguments = [path]
        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            NSLog("runScript error: \(error)")
        }
    }

    func runOutput(_ executable: String, _ args: [String]) -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: executable)
        task.arguments = args
        let pipe = Pipe()
        task.standardOutput = pipe
        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return ""
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }

    func currentMode() -> (label: String, mode: String) {
        // SleepDisabled はシステム全体設定。pmset -g の "SleepDisabled" 行から取得
        let g = runOutput("/usr/bin/pmset", ["-g"])
        var sleepDisabled = "0"
        for line in g.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("SleepDisabled") {
                let parts = trimmed.split(whereSeparator: { $0 == "\t" || $0 == " " }).map { String($0) }
                if parts.count >= 2 {
                    sleepDisabled = parts[1]
                }
            }
        }

        // バッテリー駆動時の sleep 値
        let custom = runOutput("/usr/bin/pmset", ["-g", "custom"])
        var inBattery = false
        var sleepVal = "?"
        for line in custom.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("Battery Power:") {
                inBattery = true
                continue
            }
            if trimmed.hasPrefix("AC Power:") {
                inBattery = false
                continue
            }
            if inBattery {
                let parts = trimmed.split(separator: " ", omittingEmptySubsequences: true).map { String($0) }
                if parts.count >= 2 && parts[0] == "sleep" {
                    sleepVal = parts[1]
                }
            }
        }

        if sleepVal == "0" && sleepDisabled == "1" {
            return ("🔋 Mobile", "Mobile")
        } else if sleepVal == "1" && sleepDisabled == "0" {
            return ("💤 Normal", "Normal")
        } else {
            return ("⚙️ Custom", "Custom (sleep=\(sleepVal), SleepDisabled=\(sleepDisabled))")
        }
    }

    func updateStatus() {
        let (label, mode) = currentMode()
        statusItem.button?.title = label
        if let menu = statusItem.menu, let item = menu.item(withTag: 1) {
            item.title = "現在: \(mode)"
        }
    }

    // メニューを開いた瞬間に最新状態を反映
    func menuWillOpen(_ menu: NSMenu) {
        updateStatus()
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)  // Dockに表示せずメニューバー常駐
let delegate = AppDelegate()
app.delegate = delegate
app.run()
