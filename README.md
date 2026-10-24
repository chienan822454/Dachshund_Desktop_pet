# 旺旺 — 臘腸狗桌寵（Windows）

一隻會在 Windows 桌面上走來走去的臘腸狗「旺旺」：會搖尾巴、散步、歪頭、聞聞、伸懶腰、趴下、睡午覺，還可以換衣服。

![旺旺換衣服預覽：不穿衣服、藍色小熊衣、HAPPY 恐龍衣、紅色鋪棉背心、迷彩鋪棉外套、軍綠鋪棉背心](docs/preview.png)

## 在另一台電腦下載並執行

> **請用 GitHub Desktop 下載（Clone），不要按網頁上的「Download ZIP」。**
> 從瀏覽器下載的檔案會被 Windows 標記成「從網路下載」，啟動檔會拒絕執行。
> 用 GitHub Desktop 下載的檔案沒有這個標記，可以直接執行。

1. 安裝 GitHub Desktop：<https://desktop.github.com/download/>，用你的 GitHub 帳號登入。
   （這是私人專案，別台電腦也要登入同一個帳號才看得到。）
2. 在 GitHub Desktop 選 **File → Clone repository**，選 `Dachshund_Desktop_pet`，按 **Clone**。
   預設會下載到「文件\GitHub\Dachshund_Desktop_pet」。
3. 打開那個資料夾，雙擊 `START_Dachshund.cmd`，旺旺就會出現在螢幕右下角。
4. 之後有新版本時，在 GitHub Desktop 按 **Fetch origin → Pull origin** 就會更新。

需求：Windows 10 或 11（內建的 Windows PowerShell 5.1）。不用安裝、不需要系統管理員權限。

## 怎麼玩

- **左鍵點一下**：摸摸旺旺，牠會吐舌頭開心跳一下、快速搖尾巴；牠睡著時點一下會叫醒牠。
- **左鍵拖曳**：把旺旺抱起來，放下後牠會甩甩身體。
- **右鍵選單**：
  - 叫旺旺做動作（歪頭、聞聞、甩甩頭、東張西望、伸懶腰、趴一下、坐下、打哈欠）
  - 睡覺（趴著睡、側躺曬太陽、翻肚睡、攤平曬肚子、縮成一團、窩在狗窩）、叫醒旺旺
  - 換衣服（不穿衣服、藍色小熊衣、HAPPY 恐龍衣、紅色鋪棉背心、迷彩鋪棉外套、軍綠鋪棉背心）
  - 自由走動、走動速度、追著滑鼠跑、自動汪汪叫、午睡、晚上自動睡覺（晚上10點～早上7點）、尺寸、關閉旺旺
- 完整說明請看 [使用說明.txt](使用說明.txt)。

## 安全性

- 不連網路、不安裝任何東西、不修改 Windows 設定、不需要系統管理員權限。
- 不繞過 PowerShell 的安全設定：電腦設定成「只允許簽署過的指令碼」或「不允許指令碼」時，程式不會執行，並說明原因。
- 只有出錯時，才會在自己的資料夾留下 `DachshundPet_Error_*.txt` 錯誤紀錄。

## 檔案

| 檔案 | 用途 |
|---|---|
| `START_Dachshund.cmd` | 啟動旺旺 |
| `DIAG_Dachshund.cmd` | 診斷模式（視窗會一直開著並顯示錯誤） |
| `DachshundPet.ps1` | 程式本體 |
| `dachshund_3d_*.png` | 不穿衣服的 28 張圖（姿勢和表情） |
| `clothes/` | 五件衣服（blue_bear、happy_dino、red_vest、camo_jacket、olive_vest），每件 28 張圖 |
| `使用說明.txt` | 完整使用說明 |
| `docs/preview.png` | 上面的預覽圖 |

## 無法啟動時

雙擊 `DIAG_Dachshund.cmd`，黑色視窗會用英文說明原因並停住：

- `block unsigned scripts`：這台電腦不允許執行未簽署的指令碼（公司電腦請洽 IT）。
- `downloaded from the internet`：檔案是用瀏覽器下載的，請改用 GitHub Desktop 下載。
- `locked down`：裝置管理限制了 PowerShell（請洽 IT）。
