# calm_ig（清醒IG）

通用規則見上層 `~/Developer/CLAUDE.md`（開發迴圈、何時發問、git 規則）。這份只記這個 app 自己的事。
完整計畫：`~/.claude/plans/ios-app-doom-scrolling-1-resilient-tower.md`
接手工作先讀 `HANDOFF.md`（現在做到哪、下一步；新對話用 `/pickup calm_ig`）。進度只寫在 HANDOFF.md，這份只放穩定的決定。

## 目標

- 防止 doom scrolling：看限動、讀／回私訊不受限，但 Reels、探索、推薦貼文一律擋掉
- 只給自己用、**只做 iPhone**（不做 Mac 版）、資料只存本機
- 做法：app 內 WebView 開 instagram.com 網頁版並注入過濾腳本（「乾淨版 IG」）；
  原生 IG 用 iOS 捷徑自動化導流到本 app；想發限動時可「放行」原生 IG 幾分鐘

## 功能清單

- [x] 乾淨版 IG：WebView 殼、保留登入（`lib/browser/`）
- [x] 過濾：擋 `/reels`、`/explore`（改導搜尋）、推薦與贊助貼文；首頁導到 `/?variant=following`（`lib/filter/`、`assets/filters/instagram.js`）
- [x] 放行原生 IG（5／10 分鐘）＋到期通知＋ App Intent「放行中嗎？」（`lib/pass/`、`ios/Runner/InstagramPassIntent.swift`）
- [x] 捷徑自動化設定教學頁（`lib/onboarding/`，依 iOS 27 新版捷徑寫）
- [ ] （第二階段，未決定）放行期間用 ReplayKit 截圖監控 Reels

## 技術決定

- 平台：iOS only（Flutter），最低 iOS 17（App Intent 需要）
- Bundle ID：`com.satori.calmIg`
- 不用 Screen Time API（Family Controls）：免費 Apple ID 不能用，而且只能整個 app 擋
- 不做全天截圖監控：ReplayKit 要手動開始、耗電發熱、會被系統殺掉、也關不掉 IG
- 過濾規則只有一份：`FilterConfig`（Dart）→ JSON 注入 JS；`test/js/filter_rules.test.mjs`（Node）確保兩邊一致
- 放行到期時間存 shared_preferences 的 `pass_until_ms`（UserDefaults 裡是 `flutter.pass_until_ms`），App Intent 直接讀它
- Swift 檔加進 Runner target 用 xcodeproj gem（`ruby -e 'require "xcodeproj"…'`），不手改 pbxproj

## 常用指令

```bash
flutter analyze && flutter test                       # 含 Node 跑的 JS 規則測試
flutter test integration_test -d <simulator-id>       # 在 WKWebView 裡跑過濾腳本（假 IG 頁）
flutter build ios --simulator --debug                 # → build/ios/iphonesimulator/Runner.app
```

模擬器測 App Intent：用 `xcrun simctl spawn booted defaults write "<app data container>/Library/Preferences/com.satori.calmIg" flutter.pass_until_ms -int <ms>`
寫入（container 用 `xcrun simctl get_app_container booted com.satori.calmIg data`）。**不要直接改 plist 檔**，cfprefsd 有快取會讀到舊值。

## 已知問題 / 待辦

- 已用登入的真 IG 驗證（2026-11-07）：Reels 連結是 `/reels/` 且被藏、`/explore/search/` 存在、`?variant=following` 有效、
  朋友的單支 reel 不能往下滑；首頁改成「限動列＋看追蹤中貼文連結」，推薦動態整塊藏掉（Following 頁沒有限動列，所以不能拿它當首頁）
- 2026-11-08 再驗證：限動可正常打開播放（用使用者自己的限動測，避免留下已讀）、私訊收件匣正常載入（沒點開對話，避免標成已讀）
- **通知**：app 內 WebView 沒有 Notification / PushManager / service worker，網頁版不可能推播 → 靠**原生 IG 的推播**（原生 IG 要留著、通知要開）。
  捷徑導流不會擋通知（Screen Time 才會）；點通知 → 原生 IG 打開 → 被導回清醒IG
- 未處理：「Use the app」橫幅（目前沒藏，可按 X 關）；送出私訊沒實測（不代使用者發訊息）
- 除錯工具：debug build 有 `lib/browser/debug_js_bridge.dart`，把 JS 寫進 app 的 `tmp/debug_eval.js` 就能在 IG 頁面執行
- 注意：`flutter test integration_test` 跑完會把 app 解除安裝（設定會重置；這次 IG 登入有保住，但別依賴）
- 捷徑步驟的中文按鈕名稱是從英文版模擬器翻的，要在使用者的 iPhone（繁中）上對一次
- 捷徑自動化＋原生 IG 的整段流程只能在實機測（模擬器沒有 IG）；需要使用者在 Xcode 登入免費 Apple ID
- `flutter_inappwebview_ios` 不支援 Swift Package Manager，Flutter 有警告「未來會變成錯誤」；到時候要換套件或等它更新
- App 圖示還是 Flutter 預設
