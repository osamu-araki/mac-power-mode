// Power Mode — メニューバー常駐の電源モード切替アプリ
// Version: 1.3.0 | Updated: 2026-05-10
// [2026-05-09] Chrome を SIGSTOP/SIGCONT で一時停止/再開するメニュー項目を追加
// [2026-05-09] 自動終了（AutomaticTermination）を無効化
// [2026-05-10] runOutput のパイプバッファ・デッドロックを修正
// [2026-05-10] 蓋連動オートメーション追加（Mobile Mode + 蓋閉で Chrome 自動停止/再開）

import Cocoa
import IOKit
import IOKit.pwr_mgt

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
    var autoPauseToggleItem: NSMenuItem!

    // 蓋連動の状態管理
    var notifyPort: IONotificationPortRef?
    var lidNotifierObject: io_object_t = 0
    var lastKnownLidClosed: Bool = false
    var autoPauseEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "autoPauseChromeOnLidClose") }
        set { UserDefaults.standard.set(newValue, forKey: "autoPauseChromeOnLidClose") }
    }

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

        autoPauseToggleItem = NSMenuItem(
            title: "蓋連動: Mobile Mode + 蓋閉で Chrome 自動停止",
            action: #selector(toggleAutoPause),
            keyEquivalent: ""
        )
        autoPauseToggleItem.target = self
        menu.addItem(autoPauseToggleItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "終了", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu

        // 蓋イベント購読を開始
        lastKnownLidClosed = readClamshellState()
        setupClamshellNotifications()

        updateStatus()
    }

    // MARK: - メニューアクション

    @objc func switchToMobile() {
        runScript("\(scriptsBase)/mobile-mode.sh")
        applyAutoPauseLogic()  // モード切替時にも自動停止ロジックを適用
        updateStatus()
    }

    @objc func switchToNormal() {
        runScript("\(scriptsBase)/normal-mode.sh")
        applyAutoPauseLogic()  // Normal に戻ったら必要に応じて Chrome 再開
        updateStatus()
    }

    @objc func pauseChrome() {
        runProcess("/usr/bin/pkill", ["-STOP", "-f", "Google Chrome"])
        notify(title: "🟡 Chrome 一時停止", body: "再開するまで CPU/GPU を消費しません")
        updateStatus()
    }

    @objc func resumeChrome() {
        runProcess("/usr/bin/pkill", ["-CONT", "-f", "Google Chrome"])
        notify(title: "🟢 Chrome 再開", body: "一部のWebアプリで再ログインが必要な場合があります")
        updateStatus()
    }

    @objc func toggleAutoPause() {
        autoPauseEnabled.toggle()
        // ON にした瞬間に現在の状態に合わせて Chrome を制御
        applyAutoPauseLogic()
        updateStatus()
        let label = autoPauseEnabled ? "ON" : "OFF"
        notify(title: "蓋連動オートメーション: \(label)", body: autoPauseEnabled
            ? "Mobile Mode で蓋を閉じると Chrome を自動停止します"
            : "蓋連動を無効にしました")
    }

    @objc func quitApp() {
        NSApp.terminate(nil)
    }

    // MARK: - 蓋イベント検出

    func setupClamshellNotifications() {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("IOPMrootDomain")
        )
        guard service != 0 else {
            NSLog("setupClamshellNotifications: IOPMrootDomain not found")
            return
        }

        notifyPort = IONotificationPortCreate(kIOMainPortDefault)
        guard let notifyPort = notifyPort else {
            IOObjectRelease(service)
            return
        }
        IONotificationPortSetDispatchQueue(notifyPort, DispatchQueue.main)

        let context = Unmanaged.passUnretained(self).toOpaque()

        // kIOGeneralInterest で IOPMrootDomain 配下の状態変化通知を購読
        let result = IOServiceAddInterestNotification(
            notifyPort,
            service,
            kIOGeneralInterest,
            { (refcon, _, _, _) in
                guard let refcon = refcon else { return }
                let app = Unmanaged<AppDelegate>.fromOpaque(refcon).takeUnretainedValue()
                DispatchQueue.main.async {
                    app.checkClamshellChange()
                }
            },
            context,
            &lidNotifierObject
        )

        if result != KERN_SUCCESS {
            NSLog("setupClamshellNotifications: IOServiceAddInterestNotification failed: \(result)")
        }

        // service への参照は notification 内部で保持されるので、ここでは release しない
        // （IOServiceAddInterestNotification は内部で retain する仕様）
        IOObjectRelease(service)
    }

    /// 現在の蓋状態を IOKit から読む（true = 閉、false = 開）
    func readClamshellState() -> Bool {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("IOPMrootDomain")
        )
        guard service != 0 else { return false }
        defer { IOObjectRelease(service) }

        guard let propRef = IORegistryEntryCreateCFProperty(
            service,
            "AppleClamshellState" as CFString,
            kCFAllocatorDefault,
            0
        ) else {
            return false
        }
        let value = propRef.takeRetainedValue()
        if let isClosed = value as? Bool {
            return isClosed
        }
        if let num = value as? NSNumber {
            return num.boolValue
        }
        return false
    }

    func checkClamshellChange() {
        let nowClosed = readClamshellState()
        if nowClosed != lastKnownLidClosed {
            lastKnownLidClosed = nowClosed
            applyAutoPauseLogic()
            updateStatus()
        }
    }

    /// Mobile Mode + 蓋閉 → Chrome 停止 / それ以外 → 再開
    /// SIGSTOP/SIGCONT は冪等（既に同じ状態なら no-op）なので毎回呼んで OK
    func applyAutoPauseLogic() {
        guard autoPauseEnabled else { return }
        let mode = currentMode().mode
        let shouldPause = (mode == "Mobile" && lastKnownLidClosed)
        if shouldPause {
            runProcess("/usr/bin/pkill", ["-STOP", "-f", "Google Chrome"])
        } else {
            runProcess("/usr/bin/pkill", ["-CONT", "-f", "Google Chrome"])
        }
    }

    // MARK: - プロセス実行ユーティリティ

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

    func notify(title: String, body: String) {
        // ダブルクオート・バックスラッシュをエスケープ
        let escapedTitle = title.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let escapedBody = body.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", "display notification \"\(escapedBody)\" with title \"\(escapedTitle)\""]
        try? task.run()
    }

    // MARK: - 状態判定

    func chromeState() -> ChromeState {
        let output = runOutput("/bin/ps", ["-axo", "state=,command="])
        var found = false
        var anyStopped = false
        var anyRunning = false
        for line in output.split(separator: "\n") {
            let trimmed = String(line).trimmingCharacters(in: .whitespaces)
            guard trimmed.contains("Google Chrome") else { continue }
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
        if anyStopped && !anyRunning { return .stopped }
        return .running
    }

    func currentMode() -> (label: String, mode: String) {
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

    // MARK: - UI 更新

    func updateStatus() {
        let (label, mode) = currentMode()
        statusItem.button?.title = label
        if let menu = statusItem.menu, let item = menu.item(withTag: 1) {
            let lidLabel = lastKnownLidClosed ? "蓋: 閉" : "蓋: 開"
            item.title = "現在: \(mode) | \(lidLabel)"
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

        // 蓋連動トグル項目のチェックマーク
        autoPauseToggleItem.state = autoPauseEnabled ? .on : .off
    }

    // メニューを開いた瞬間に最新状態を反映
    func menuWillOpen(_ menu: NSMenu) {
        // 念のため蓋状態も再読込（通知を取りこぼした場合の保険）
        lastKnownLidClosed = readClamshellState()
        updateStatus()
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
