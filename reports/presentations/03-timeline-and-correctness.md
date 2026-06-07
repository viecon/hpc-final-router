# 時間線與正確性簡報

日期：2026-06-06

## 投影片 1 - 為什麼要區分時間線

repo 裡的結果來自多個實作時期。這些數字不能混在一起講：

- 早期 best-per-benchmark portfolios；
- Slurm 16-case matrix runs；
- VM utilization probes；
- VM final global-strategy runs；
- final 之後的 negative probes。

報告任何數字時，都要說清楚 date、commit、denominator、benchmark set，以及
這是 portfolio、single global strategy，還是 runtime frontier。

## 投影片 2 - 實驗時期整理

| 日期 | 主要檔案 | 策略狀態 | 可以安全宣稱的內容 |
| --- | --- | --- | --- |
| 2026-05-27 | `../../docs/10-early-source-strategy-report.md`, `../../docs/11-early-results-summary.md` | 早期 source methods：`OpenMP`, fast layer, `P2/P3`, `CUDA`, edge-count。 | adaptec1-3 legal NTHU speedup `2.325883x`；16-case matrix 是廣泛 evidence。 |
| 2026-06-04 | `../../docs/23-wl-guard-speedup.md`, `../../docs/24-wl120-single-core-results.md`, `../../docs/25-overall-adaptive-router-results.md` | Net-guided low-layer 與 adaptive repair 開發期。 | `WL<=1.2` legal7 `1.961x`；one global strategy legal7 `1.771x`。 |
| 2026-06-05 | `../03-final-vm-strategy-results.md`, `../04-main-vs-final-router-comparison.md` | High-overflow `P2` final strategy。 | requested12 `1.345x`，legal7 `1.752x`，total overflow `166`。 |
| 2026-06-05 later | `../05-wl-speed-literature-and-probes.md`, `../06-bounded-length-reroute-probe.md` | Layer-penalty 與 bounded-length probes。 | negative results；final 仍保持 bounded off。 |
| 2026-06-06 | `../01-final-router-optimization-zh.md`, presentation deck set | 整理與簡報，不新增 benchmark row。 | 用於口頭報告；數字仍要回追到上面 dated files。 |

## 投影片 3 - Correctness guard

Final strategy 的 correctness target：

- 如果 original 在某個 benchmark 是 legal，optimized 必須保持
  `overflow=0,max_overflow=0`；
- requested12 裡包含 original-overflow hard cases，所以那些 case 用 overflow
  reduction 和 residual overflow 評估。

最新 final 狀態：

| 範圍 | 合法 rows | Total overflow | Max overflow | Guard |
| --- | ---: | ---: | ---: | --- |
| original-legal 7 | 7/7 | 0 | 0 | pass |
| requested12 | 10/12 | 166 | 2 | `bigblue2` / `newblue1` still residual |

## 投影片 4 - Portfolio vs single global strategy

Portfolio examples：

- 早期 adaptec1-3 best legal combination；
- fastest guarded 12-case portfolio；
- `WL<=1.2` legal7 portfolio。

Single global strategy examples：

- overall adaptive router；
- high-overflow adaptive `P2` final strategy。

重要區別：

> Portfolio 是用來看上限和診斷方向；final router claim 應該使用同一套全域策略，
> 由 routing-state signals 控制，而不是依 testcase name 手動切換。

## 投影片 5 - 被保留的時間線

| 階段 | 被保留的想法 | 原因 |
| --- | --- | --- |
| early fast layer | fast layer assignment | 第一個有明顯速度效果的方向。 |
| `WL` guard | net-guided low-layer assignment | 把 `WL` inflation 從約 1.7x-1.9x 降到 legal7 約 1.12x。 |
| adaptive repair | measured-overflow trigger | 恢復 original-legal correctness。 |
| high-overflow `P2` | overflow 高時才增加 `P2` budget | 改善 hard-case overflow，且不影響 legal7 path。 |

## 投影片 6 - 被拒絕的時間線

| 階段 | 被拒絕的想法 | 原因 |
| --- | --- | --- |
| `OpenMP` scans | 當 main speed claim | 正確但只有約 `1.03x`。 |
| parallel reroute prototype | 預設啟用 | CPU 使用率較高，但更慢，且 direct maze commit 風險高。 |
| `CUDA` dual GPU | 用來降低 single-testcase latency | GPU1 幾乎閒置或 overhead 抵消收益。 |
| edge-count frontier | 當 final claim | 很快但大多 illegal。 |
| strict legal maze | final 預設啟用 | plateau 或 post-accept variant crash。 |
| layer penalty tuning | 降低 `WL` / `overflow` | probe 中沒有改變 `WL` 或 `overflow`。 |
| bounded-length reject-only | final 預設啟用 | safe version 正確但太慢。 |

## 投影片 7 - 數字引用來源

簡報中講到數字時，引用下面來源：

| 數字宣稱 | 來源 |
| --- | --- |
| latest final requested12 `1.294x`, overflow `166` | `../06-bounded-length-reroute-probe.md` final recheck |
| earlier clean selected requested12 `1.345x` | `../03-final-vm-strategy-results.md` |
| current vs same-CLI main `1.677x` | `../04-main-vs-final-router-comparison.md` |
| `WL<=1.2` legal7 `1.961x` | `../../docs/24-wl120-single-core-results.md` |
| `OpenMP` / `CUDA` utilization | `../../docs/21-vm-multicore-utilization-log.md`, `../../docs/22-vm-cuda-utilization-log.md` |
| method / commit map | `../02-methods-by-commit-and-result.md` |

## 投影片 8 - 最後講法

建議口頭版：

> 最後版本是一套 adaptive NTHU-Route global strategy，不 hardcode testcase
> names。它保持所有 original-legal cases 合法，requested12 平均 `WL` 約 1.16x，
> 並把 total overflow 降到 166。更快的結果存在，但那些是 portfolio、high-WL
> rows，或 illegal runtime frontier，不能當作 final legal router claim。

Raw evidence map：

- `../../docs/00-evidence-index.md`
