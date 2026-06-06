# 效能與分數品質簡報

日期：2026-06-06

## 投影片 1 - 問題是什麼：VLSI Global Routing

Global routing 是晶片實體設計中的繞線規劃問題。輸入是一張 routing
grid、許多要連接的 nets，以及每條 grid edge 的容量限制。

Router 要同時做到三件事：

- 把所有 nets 連起來；
- wirelength 不要太長；
- 不要讓任何 edge 的使用量超過 capacity，也就是 `overflow=0`。

因此本專題的效能不是只看 runtime。跑得快但留下 overflow，或 wirelength
暴增，都不能直接當成好的 router。

## 投影片 2 - 為什麼要做這個主題

Global routing 會在 physical design flow 中反覆執行，runtime 直接影響設計
迭代速度。NTHU-Route 2.0 有 source code，可以真的修改 routing policy，而不
只是換一個 black-box router。

我們的目標是比較「沒有加速的 NTHU-Route」與「修改後 NTHU-Route」：

- 速度有沒有變快；
- 原本就合法的測資有沒有保持合法；
- 原本 overflow 的困難測資有沒有改善；
- wirelength 有沒有控制在合理範圍。

## 投影片 3 - 測資與原本速度

這輪 VM 實驗使用 12 筆指定測資：

```text
adaptec1-5
bigblue1-3
newblue1, newblue2, newblue5, newblue6
```

原始 NTHU-Route baseline：

| 範圍 | 測資數 | 原始 runtime | 原始 legality |
| --- | --- | ---: | --- |
| requested12 | 12 | 12295.597s | 7/12 legal |
| 原本合法 subset | 7 | 6853.445s | 7/7 legal |
| 原本 overflow subset | 5 | 5442.152s | 0/5 legal |

原本合法的 7 筆是 `adaptec1`, `adaptec3`, `adaptec4`, `adaptec5`,
`bigblue1`, `newblue2`, `newblue6`。這些 case 是 correctness guard：加速後
不能把它們弄壞。

資料來源：`../03-final-vm-strategy-results.md`,
`../../docs/00-evidence-index.md`

## 投影片 4 - 從 main branch docs 找到的起點

我先完整閱讀 `origin/main` 的 `docs/`，確認上一版已經知道幾件事：

| 前版文件觀察 | 對後續優化的意義 |
| --- | --- |
| 原始 flow 是 FLUTE tree -> P2 rip-up/reroute -> P3 post-processing -> layer assignment。 | 優化要講清楚插在哪個階段。 |
| 主要時間在 `route_all_2pin_net()` / `specify_all_range()`，不是簡單 reduction。 | 只加 OpenMP 到 overflow/WL scan 不會有大幅加速。 |
| fast greedy layer assignment 能明顯加速，但 WL 會變大。 | 可當速度方向，但要加 WL guard。 |
| P2/P3 budget tuning 能省時間，但太早停會留下 overflow。 | 需要 adaptive repair，而不是固定少跑。 |
| CUDA scorer 單獨很快，但 end-to-end 被 sequential routing flow 卡住。 | GPU 要 batching 才可能有效，不能直接當 final。 |

所以我們不是從「多開核心」開始，而是從 routing effort 花在哪裡開始調整。

已檢查 `origin/main` 上的舊版 docs；目前 branch 的改名後對應檔案：
`../../docs/10-early-source-strategy-report.md`,
`../../docs/11-early-results-summary.md`,
`../../docs/32-gpu-feasibility-notes.md`

## 投影片 5 - 為什麼不能直接平行化：分 routing 階段看

不是所有階段都不能平行，而是最花時間的階段很難安全平行。

| Routing 階段 | 能不能平行 | 原因 |
| --- | --- | --- |
| Input parsing / FLUTE tree | 可以部分平行，但時間占比小 | 不是主要 bottleneck，平行後對 end-to-end 幫助有限。 |
| Congestion / `wirelength` scan | 可以平行 | 這類 scan/reduction 已用 `OpenMP` 試過，正確但整體只有約 `1.03x`。 |
| `P2 rip-up/reroute` | 最難直接平行 | 每條 net 會 rip-up 舊 path、更新 shared `congestion map`、再 commit 新 path；下一條 net 的 cost 依賴前一條的更新結果。 |
| `P3 post-processing` | candidate scoring 可平行，commit 很難 | 多個 candidate 可以先算分，但真正修改 route 時仍會碰到 shared state 和 route order。 |
| Layer assignment | 可替換策略，比平行化更有效 | 我們改成 net-guided fast layer，不是靠多 thread。 |
| Output / checker | 可平行但不是瓶頸 | 對 router runtime 幫助不大。 |

所以真正問題不是「不能用多核」，而是 current code 的核心 mutation loop 是
order-sensitive。直接加 lock 會把它序列化；硬做 batch 則要付出 conflict
detection、fallback、route order 變動的成本。

## 投影片 6 - 現在的加速方法

最後版本使用同一套全域策略，不根據測資名稱 hardcode。

核心想法：

| 方法 | 做法 | 為什麼加速或改善結果 |
| --- | --- | --- |
| Net-guided fast layer | layer assignment 走較快的 greedy path，但讓同一個 net 優先走一致、低且合法的 layer。 | 保留 fast layer 的速度，同時降低 WL/overflow 爆炸。 |
| Adaptive legal repair | 先跑較短 initial repair，量測 overflow 後再決定是否繼續修。 | 不在簡單 case 浪費時間，也不直接放掉困難 case。 |
| High-overflow P2 budget | 若 repair-entry overflow 很高，才把 P2 max iteration 提到 24。 | 對 hard cases 增加修復能力，避免固定 budget 對所有 case 都過重。 |
| Edge-count P3 priority | post-processing 優先處理碰到最多 overflow edges 的 two-pin nets。 | 把有限 reroute effort 花在最可能降低 overflow 的地方。 |

白話說法：不是每個測資手動挑最快版本，而是 router 看目前 routing 狀態，決定
要多修還是少修。

## 投影片 7 - 整體結果：原本 vs 加速後

| 範圍 | Original s | Current s | Speedup | WL ratio | Legality |
| --- | ---: | ---: | ---: | --- | --- |
| requested12 latest recheck | 12295.597 | 9501.285 | 1.294x | avg 1.158, worst 1.284 | 10/12 legal, overflow 166 |
| requested12 clean selected run | 12295.597 | 9144.395 | 1.345x | avg 1.158, worst 1.284 | 10/12 legal, overflow 166 |
| 原本合法 7 筆 latest recheck | 6853.445 | 4061.935 | 1.687x | avg 1.118, worst 1.151 | 7/7 legal |
| 原本合法 7 筆 clean run | 6853.445 | 3910.736 | 1.752x | avg 1.118, worst 1.151 | 7/7 legal |

重點：原本不 overflow 的 7 筆全部保持合法；整體 12 筆從 7/12 legal 改善到
10/12 legal，剩下 residual overflow 在 `bigblue2` 和 `newblue1`。

## 投影片 8 - 每個測資差在哪裡

Clean selected run 的逐測資結果：

| Benchmark | 原始是否合法 | Original s | Current s | Speedup | Current overflow |
| --- | --- | ---: | ---: | ---: | ---: |
| adaptec1 | yes | 441.963 | 356.407 | 1.240x | 0 / 0 |
| adaptec2 | no | 173.992 | 292.934 | 0.594x | 0 / 0 |
| adaptec3 | yes | 479.186 | 456.877 | 1.049x | 0 / 0 |
| adaptec4 | yes | 130.667 | 125.637 | 1.040x | 0 / 0 |
| adaptec5 | yes | 1240.592 | 857.268 | 1.447x | 0 / 0 |
| bigblue1 | yes | 1206.307 | 752.409 | 1.603x | 0 / 0 |
| bigblue2 | no | 1020.139 | 1084.253 | 0.941x | 68 / 2 |
| bigblue3 | no | 907.876 | 887.277 | 1.023x | 0 / 0 |
| newblue1 | no | 1043.267 | 1106.592 | 0.943x | 98 / 2 |
| newblue2 | yes | 76.516 | 57.217 | 1.337x | 0 / 0 |
| newblue5 | no | 2296.878 | 1862.603 | 1.233x | 0 / 0 |
| newblue6 | yes | 3278.214 | 1304.920 | 2.512x | 0 / 0 |

解讀：

- 原本合法的 7 筆全部保持合法，而且總時間約 1.75x。
- 原本 overflow 的 5 筆中，有 3 筆修到 `0 / 0`。
- `bigblue2` 和 `newblue1` 還沒完全合法，但 overflow 已壓到很小。

資料來源：`../03-final-vm-strategy-results.md`

## 投影片 9 - 跟 main branch 同 CLI 比較

資料來源：`../04-main-vs-final-router-comparison.md`

| 指標 | `main` 6f44073 | Current d1b7584 |
| --- | ---: | ---: |
| 總秒數 | 16441.272 | 9804.449 |
| Speedup | 1.000x | 1.677x |
| 合法 rows | 4/12 | 10/12 |
| Total overflow | 20851542 | 166 |
| 平均 current/main WL ratio | 1.000 | 1.200 |
| 最差 current/main WL ratio | 1.000 | 1.399 |

這張投影片的用途是回答「有加速跟沒加速到底差在哪」。同一組 CLI budget 下，
`main` 很多 case 仍然花很久且留下大量 overflow；current 透過 adaptive repair
和 layer strategy，把 legality 從 4/12 拉到 10/12，同時總時間縮短。

## 投影片 10 - 為什麼不是直接用多核或 CUDA

| Direction | 實驗結果 | 結論 |
| --- | --- | --- |
| OpenMP scan/reduction | requested12 約 1.03x；adaptec1-3 約 1.009x。 | 正確但不是主要瓶頸。 |
| 12-thread OpenMP | `newblue2` 65.647s -> 63.587s，CPU 約 103%。 | thread 有開，但主要 mutation loop 仍接近單核心。 |
| conflict-aware parallel reroute | `newblue2` best 80.255s，比 default 65.739s 慢。 | CPU 利用率變高，但 route order/fallback 成本更大。 |
| CUDA single/dual GPU | `adaptec3` 約 191-200s，GPU 平均 util <0.2%。 | GPU work 太小且被 CPU sequential flow 切碎。 |

結論：目前最有效的不是硬把 loop 平行化，而是減少不必要 repair、把 repair effort
花在真正 overflow 的地方。

## 投影片 11 - 快速但不能當 final 的結果

前面實驗有些數字很快，但不能混成最後成果：

| 結果類型 | 例子 | 為什麼不能直接當 final |
| --- | --- | --- |
| quality-sensitive portfolio | WL<=1.2 legal7 portfolio: 1.961x | 這是多個版本中挑每個 case 的好結果，不是一套固定 router。 |
| runtime frontier | requested12 edge-count: 5.38x | 很快，但 legal coverage 只有約 2/12。 |
| fastest guarded portfolio | requested12 3.17x | 原本合法 case 有守住，但 WL 偏大，hard cases 仍有 overflow。 |

這些結果的價值是告訴我們「速度上限在哪裡」和「哪個方向有潛力」，但最後報告要用
同一套全域策略的結果。

## 投影片 12 - 最後可以怎麼講

建議口頭版：

> 我們研究的是 NTHU-Route 在 ISPD08 global routing 上的 source-level 加速。
> 從 main branch docs 和 profiling 可知，瓶頸不是簡單 reduction，而是
> sequential rip-up/reroute 與修 overflow 的 effort 分配。因此最後沒有主打
> OpenMP 或 CUDA，而是改 layer assignment、adaptive repair、high-overflow P2
> budget 和 overflow-edge priority。結果在 12 筆指定測資上約 1.29x-1.35x，
> 在原本合法的 7 筆上約 1.69x-1.75x，且這 7 筆全部保持合法。

原始證據：

- `../../docs/00-evidence-index.md`
- `../02-methods-by-commit-and-result.md`
- `../01-final-router-optimization-zh.md`
