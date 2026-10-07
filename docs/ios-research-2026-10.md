# Typeless 與同類 iOS 語音鍵盤的做法（2026-10-07 調查）

結論：**沒有一家是在鍵盤擴充裡錄音的**。Apple 不讓 keyboard extension 開麥克風，就算開了 Full Access 也一樣（錯誤訊息是 extension 沒有 record audio 的 entitlement）。所以做法都是：鍵盤只負責畫面和插字，錄音交給主 App 在背景做。

## 各家怎麼讓主 App 在背景錄音

| | 保持在背景的方式 | 怎麼回到原本的 App | 來源 |
|---|---|---|---|
| Typeless | Picture in Picture：開「Skip app switching」後，主 App 以 PiP 小視窗常駐，可以拖到螢幕邊緣藏起來。Speak 鍵的麥克風空心表示「這次會跳 App」，實心表示「可以直接說」（V2.2.0） | 官方沒寫，只說回到原本的 App 之後 | typeless.com/help/release-notes/ios/picture-in-picture 、…/when-does-app-switching-happen |
| Wispr Flow | 「Flow session」有時效，可設 5 分、15 分、1 小時或永不 | 用戶按 OK 或往右滑；返回沒完成的話，10 秒後清除 | docs.wisprflow.ai |
| superwhisper | — | iOS 26.4 起「no longer returns you to your previous app. Swipe back instead.」 | superwhisper.com/docs/get-started/ios |

- iOS 26.4 之後，`_hostBundleID`、`LSApplicationWorkspace` 等取得或回到 host App 的私有方法全部失效。Apple DTS 確認沒有公開 API（developer forums 826851、841057、843118）。
- Typeless 被抱怨的副作用：麥克風用完還一直開著、連 CarPlay 時音樂被切成通話音質、螢幕不會自動鎖、耗電（App Store 評論，2026-03～09）。

## Typeless iPhone 鍵盤的功能

- **Speak 鍵**：點一下開始、再點一下結束。鍵盤收起或切到別的 App 時仍在錄，回到輸入框再按一次才結束（1.7.0）。
- **錄音上限**：單次 9 分鐘，第 8 分鐘開始倒數。
- **語音鍵盤與打字鍵盤分開**：左右滑切換，支援 36 種語言；注音約在 2026-08 加入，但用戶抱怨字庫太少。
- **Speak to edit**：選取一段字，用說的下指令修改。
- **Help me write**（2.7.0，2026-09）：說出需求，直接生成整段文字。
- **Translate**：可以設多個目標語言，按住 Speak 往上滑選擇。
- **Ask anything 只有桌面版有**，手機用戶也抱怨缺少這類功能。
- **個人字典**：手動新增，修正過的字也會自動加入。
- **個人化**：自動學習用戶風格，「nothing to set up」。
- **依 App 調整語氣**。
- **沒有自訂 prompt**：官方比較頁說 Wispr 是「fixed style presets」，Typeless 則是自動適應。
- **History**：存在裝置上，可以重試、分享音檔；2.5.0 起有 Cloud Sync。
- **其他入口**：Action Button、控制中心、捷徑、Siri、Widget 都沒有。Wispr Flow 有 Action Button。
- **評價**：好評集中在品質最好、可以長時間口述。最常見的抱怨是「錄完沒插入任何字也沒報錯」、「被改寫得像摘要」、「麥克風一直開／不鎖屏／耗電」。
- **價格**：Pro 每月 US$30，年繳每月 US$12。免費版從 9/22 起變成每週 2,000 字。

## 對 Atype iPhone 版的意涵

1. 錄音放主 App；鍵盤和主 App 之間用 App Group 加 Darwin notification 溝通。
2. 背景待命要有時限，而且閒置時要真的關掉 AVAudioSession，不要學 Typeless 讓麥克風一直開著。
3. 用麥克風圖示（空心／實心）事先告訴用戶這次會不會跳到 App。
4. 不做自動返回原 App，引導用戶用左上角的「◀ App」或往右滑回去。
5. 錄完一定要有結果：先存音檔和原始辨識結果，失敗就明確顯示錯誤，並提供重試。
6. 自訂提示詞是差異化重點，Typeless 手機版沒有這個功能。
7. 補上 Typeless 沒有的入口：Action Button、控制中心、捷徑（App Intents）。
8. 錄完立刻釋放音訊，避免 CarPlay 或藍牙耳機被切成通話音質。
