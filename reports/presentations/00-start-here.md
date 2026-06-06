# 簡報從這裡開始

日期：2026-06-06

這份檔案是準備簡報時的入口。目標是先把故事線講清楚，再用 raw data 和
完整 report 做備用資料。

## 建議閱讀順序

| 順序 | 檔案 | 先看它的原因 |
| ---: | --- | --- |
| 1 | `01-performance-and-score.md` | 從 `global routing` 問題、測資、原始速度、`main` bottleneck 講到最後 speedup。 |
| 2 | `02-optimization-methods.md` | 說明實際改了哪些 router 邏輯，以及為什麼有些優化有效、有些無效。 |
| 3 | `03-timeline-and-correctness.md` | 區分早期 diagnostic portfolio、VM probe、最後單一全域策略，以及被拒絕的實驗。 |
| 4 | `../01-final-router-optimization-zh.md` | 完整中文報告，可拿來做詳細說明或備用投影片。 |
| 5 | `../07-scoring-methodology.md` | 先確認 score 定義：同一 config 的 total-time speedup，geomean 只作輔助。 |
| 6 | `../../docs/00-evidence-index.md` | 要查某個數字的時間、commit、VM result root 時看這份。 |

## 簡報主線

短簡報建議照這個順序：

1. 介紹問題：`global routing` 是在 capacity-limited grid 上連接 nets。
2. 說明目標：runtime 要快，但 `wirelength` 和 `overflow` 不能壞。
3. 列出測資和原始 NTHU-Route runtime。
4. 說明從 `origin/main` docs 讀到的前版問題：主要瓶頸是 sequential
   `rip-up/reroute` 和 repair effort 分配，不是單純 scan/reduction。
5. 用 routing pipeline 分階段解釋為什麼不能直接平行化：哪些階段可平行、
   哪些階段會被 shared `congestion map` 和 route order 卡住。
6. 說明目前加速策略：net-guided fast layer、adaptive repair、
   high-overflow `P2` budget、edge-count priority。
7. 比較原本與加速後的 runtime、`WL ratio`、`overflow`、原本合法 case 是否保持合法。
8. 說明為什麼有些更快結果不能當正式 score：diagnostic portfolio、高 `WL`、illegal
   runtime frontier。
9. 收斂到未來工作：真正的多核/GPU 需要 batching route proposals，不能只加
   `OpenMP pragma` 或多開 GPU。

## 技術備用資料

如果聽眾想看更細的 implementation：

1. 從上述短簡報開始。
2. 加上 `../02-methods-by-commit-and-result.md` 的 method table。
3. 加上 `../../docs/21-vm-multicore-utilization-log.md` 和
   `../../docs/22-vm-cuda-utilization-log.md` 的 utilization evidence。
4. 只有在被問 reproducibility 時，再打開 `../../docs/00-evidence-index.md`
   裡的 result roots。

## 檔名規則

- `reports/presentations/00-*`：簡報入口。
- `reports/presentations/01-*`：問題、效能、分數品質。
- `reports/presentations/02-*`：優化方法與實作邏輯。
- `reports/presentations/03-*`：時間線與正確性 guard。
- `reports/01-*`：最後整理報告。
- `reports/02-*` 到 `06-*`：方法、比較、probe 的支援報告。
- `docs/00-*`：raw evidence index。
- `docs/10-*`：早期 source/Slurm 實驗 notes。
- `docs/20-*`：VM 實驗與 utilization logs。
- `docs/30-*`：設計 notes。
- `docs/40-*`：runbook 和 rerun plans。
- `docs/90-*`：舊規劃資料。
