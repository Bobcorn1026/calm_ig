# calm_ig（清醒IG）

通用規則見上層 `~/Developer/CLAUDE.md`（開發迴圈、何時發問、git 規則）。這份只記這個 app 自己的事。
完整計畫：`~/.claude/plans/ios-app-doom-scrolling-1-resilient-tower.md`

## 目標

- 防止 doom scrolling：看限動、讀／回私訊不受限，但 Reels、探索、推薦貼文一律擋掉
- 只給自己用、**只做 iPhone**（不做 Mac 版）、資料只存本機
- 做法：app 內 WebView 開 instagram.com 網頁版並注入過濾腳本（「乾淨版 IG」）；
  原生 IG 用 iOS 捷徑自動化導流到本 app；想發限動時可「放行」原生 IG 幾分鐘

## 功能清單

- [ ] 乾淨版 IG：WebView 殼、保留登入
- [ ] 過濾：擋 `/reels/`、`/explore/`、推薦與贊助貼文；首頁導到追蹤中動態 `/?variant=following`
- [ ] 放行原生 IG（5／10 分鐘）＋到期通知＋ App Intent「放行中嗎？」
- [ ] 捷徑自動化設定教學頁
- [ ] （第二階段，未決定）放行期間用 ReplayKit 截圖監控 Reels

## 技術決定

- 平台：iOS only（Flutter），最低 iOS 17（App Intent 需要）
- Bundle ID：`com.satori.calmIg`
- 不用 Screen Time API（Family Controls）：免費 Apple ID 不能用，而且只能整個 app 擋
- 不做全天截圖監控：ReplayKit 要手動開始、耗電發熱、會被系統殺掉、也關不掉 IG

## 常用指令

```bash
flutter analyze && flutter test
flutter build ios --simulator --debug     # → build/ios/iphonesimulator/Runner.app
```

## 已知問題 / 待辦

- （無）
