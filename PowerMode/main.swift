// Power Mode — メニューバー常駐の電源モード切替アプリ
// Version: 1.2.2 | Updated: 2026-05-10
// [2026-05-09] Chrome を SIGSTOP/SIGCONT で一時停止/再開するメニュー項目を追加
// [2026-05-09] 自動終了（AutomaticTermination）を無効化
// [2026-05-10] runOutput のパイプバッファ・デッドロックを修正（メニュー無反応の真因）

import Cocoa

enum ChromeState {
    case notRunning
    case running
    case stopped
}

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var statusItem: NSStatusItem!
    var chromePauseItem: NSMenuItem!
    var chromeResumeItem: NSMenuItem!
    var chromeSeparatorItem: NSMenuItem!

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
        // メニューバー常駐アプリは macOS の Automatic Termination 対象になりやすく、
        // アイドルと判定されると裏で kill → アイコンだけが Control Center にゾンビ化し、
        // クリックが効かなくなる。これを明示的に無効化する。
        ProcessInfo.processInfo.disableAutomaticTermination("Power Mode は常駐アプリのため自動終了させない")
        ProcessInfo.processInfo.disableSuddenTermination()

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

        chromeSeparatorItem = NSMenuItem.separator()
        menu.addItem(chromeSeparatorItem)

        chromePauseItem = NSMenuItem(title: "Chrome を一時停止", action: #selector(pauseChrome), keyEquivalent: "")
        chromePauseItem.target = self
        menu.addItem(chromePauseItem)

        chromeResumeItem = NSMenuItem(title: "Chrome を再開", action: #selector(resumeChrome), keyEquivalent: "")
        chromeResumeItem.target = self
        menu.addItem(chromeResumeItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "終了", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        updateStatus()
    }

    @objc func pauseChrome() {
        // Chrome の全プロセス（メイン + Helper群）に SIGSTOP を送信
        runProcess("/usr/bin/pkill", ["-STOP", "-f", "Google Chrome"])
        notify(title: "🟡 Chrome 一時停止", body: "再開するまで CPU/GPU を消費しません")
        updateStatus()
    }

    @objc func resumeChrome() {
        runProcess("/usr/bin/pkill", ["-CONT", "-f", "Google Chrome"])
        notify(title: "🟢 Chrome 再開", body: "一部のWebアプリで再ログインが必要な場合があります")
        updateStatus()
    }

    func runProcess(_ executable: String, _ args: [String]) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: executable)
        task.arguments = args
        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            NSLog("runProcess error: \(error)")
        }
    }

    func notify(title: String, body: String) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", "display notification \"\(body)\" with title \"\(title)\""]
        try? task.run()
    }

    func chromeState() -> ChromeState {
        // ps の state 列の先頭文字で判定（T = stopped）
        let output = runOutput("/bin/ps", ["-axo", "state=,command="])
        var found = false
        var anyStopped = false
        var anyRunning = false
        for line in output.split(separator: "\n") {
            let trimmed = String(line).trimmingCharacters(in: .whitespaces)
            guard trimmed.contains("Google Chrome") else { continue }
            // ヘルパー以外の "Google Chrome" を確実に拾う（自分自身は除外）
            guard !trimmed.contains("PowerMode") else { continue }
            found = true
            if let firstChar = trimmed.first {
                if firstChar == "T" {
                    anyStopped = true
                } else {
                    anyRunning = true
                }
            }
        }
        if !found { return .notRunning }
        // 全プロセスがT状態のときのみ "stopped" 扱い
        if anyStopped && !anyRunning { return .stopped }
        return .running
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
        // 注意: パイプバッファ（macOSで通常64KB）を超える出力がある場合、
        // waitUntilExit() を先に呼ぶと子プロセスの書き込みが詰まり双方が待ち続けてデッドロックする。
        // ps -axo state=,command= は容易に64KBを超えるため、readDataToEndOfFile() を先に呼ぶ。
        let task = Process()
        task.executableURL = URL(fileURLWithPath: executable)
        task.arguments = args
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()  // stderr は捨てる
        do {
            try task.run()
        } catch {
            return ""
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
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

        // Chrome 状態に応じてメニュー項目を出し分け
        let cs = chromeState()
        switch cs {
        case .notRunning:
            chromePauseItem.isHidden = true
            chromeResumeItem.isHidden = true
            chromeSeparatorItem.isHidden = true
        case .running:
            chromePauseItem.isHidden = false
            chromeResumeItem.isHidden = true
            chromeSeparatorItem.isHidden = false
        case .stopped:
            chromePauseItem.isHidden = true
            chromeResumeItem.isHidden = false
            chromeSeparatorItem.isHidden = false
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
