// Power Mode — メニューバー常駐の電源モード切替アプリ
// Version: 1.5.0 | Updated: 2026-05-10
// [2026-05-09] Chrome の SIGSTOP/SIGCONT 制御
// [2026-05-09] 自動終了（AutomaticTermination）を無効化
// [2026-05-10] runOutput のパイプバッファ・デッドロックを修正
// [2026-05-10] 蓋連動オートメーション追加
// [2026-05-10] UI を簡素化: Chrome の手動操作・opt-in トグルを撤去し、常時自動連動に統一

import Cocoa
import IOKit
import IOKit.pwr_mgt

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var statusItem: NSStatusItem!

    // 蓋連動の状態管理
    var notifyPort: IONotificationPortRef?
    var lidNotifierObject: io_object_t = 0
    var lastKnownLidClosed: Bool = false

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
        applyAutoPauseLogic()  // モード切替時に Chrome 状態を整合
        updateStatus()
    }

    @objc func switchToNormal() {
        runScript("\(scriptsBase)/normal-mode.sh")
        applyAutoPauseLogic()  // Normal に戻ったら Chrome を再開
        updateStatus()
    }

    @objc func quitApp() {
        // 終了時に Chrome が停止状態だったら再開してから終了（取り残し防止）
        runProcess("/usr/bin/pkill", ["-CONT", "-f", "Google Chrome"])
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
        // readDataToEndOfFile() を先に呼ぶ。
        let task = Process()
        task.executableURL = URL(fileURLWithPath: executable)
        task.arguments = args
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        do {
            try task.run()
        } catch {
            return ""
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }

    // MARK: - モード判定

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
