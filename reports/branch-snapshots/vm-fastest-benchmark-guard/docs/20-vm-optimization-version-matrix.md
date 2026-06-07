# Router Optimization Version Comparison Report

Date: 2026-06-04
Branch: `vm-fastest-benchmark-guard`
Latest report scope: includes multicore prototype through code commit `e648e19`

## 1. Report Goal

本報告重點不是只列最快結果，而是比較不同版本做了什麼優化、每個版本和
`external/nthu-route-original` 的時間與成果差多少，以及如何透過邏輯比較找到
真正出問題的程式段落。

所有測試與 benchmark 都只在 VM 上執行。`external/nthu-route-original` 保持不修改，
作為 original baseline。

主要 VM 結果來源：

```text
/home/ubuntu/hpc-final-router/results/vm_real_matrix/summary_live.csv
/home/ubuntu/hpc-final-router/results/vm_wl_guard/runs/legal7_netguided_69f3eb7_20260604T042504Z
/home/ubuntu/hpc-final-router/results/vm_openmp_utilization/
/home/ubuntu/hpc-final-router/results/vm_cuda_utilization/
```

VM 環境：16 vCPU、164 GiB memory、2x Tesla V100-SXM2-32GB、Apptainer container、
`lab2-verifier.py`。

## 2. Optimization Versions

| Version / Strategy | Main Change | Target | Result Summary |
| --- | --- | --- | --- |
| `true_original` | 原始 NTHU-Route | baseline | 12 cases total `12295.597s`; 7/12 原本合法。 |
| `nthu_openmp_t4/t12` | OpenMP 化 reduction/scan kernels | 多核心加速 | 正確但幾乎沒加速；12-case `nthu_openmp_t4` 只有 `1.03x`。 |
| `nthu_fast_layer` | 用 fast greedy layer assignment 取代原 KLAT/DP layer assignment | 加速 layer assignment | 12-case `1.59x`，原本合法 7/7 仍合法，但 legal-case 平均 WL ratio `1.743`。 |
| `nthu_p2p3_budget` | 降低 P2/P3 routing effort | 減少 reroute 時間 | 單點有快，但 legal coverage 掉到 4/7；固定 budget 不夠穩。 |
| `nthu_fast_layer_repair` / `nthu_p2p3_legal_repair` | 加 conservative repair | 修 original-legal overflow | 7/7 original-legal 可修合法，但 WL 仍約 `1.74x`。 |
| `nthu_edgecount_post` | overflow edge count 優先 post-processing，限制 reroute 數 | speed frontier | 12-case `5.38x`，但 legal coverage 只有 2/12；適合證明速度上限，不適合 final legal 設定。 |
| `nthu_cuda_score` | CUDA costed-maze / dogleg scoring | GPU 局部加速 | selected cases 有用，但整體不穩；dual GPU 對單 testcase 無 latency 改善。 |
| `fast_layer_netguided_budget/repair` | 新增 net-guided fast layer：每個 net 先選 preferred layer，再局部避開 overflow | 保住 WL 同時加速 | legal7 在 `WL<=1.5x` 下達到 `2.05x`，7/7 zero overflow。 |

## 3. Aggregate Comparison Against Original

12-case aggregate uses `adaptec1-5`, `bigblue1-3`, `newblue1,2,5,6`.

| Strategy | Completed | Total s | Speedup vs original | Legal rows | Original-legal guard | Avg WL ratio on original-legal | Worst WL ratio |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `nthu_openmp_t4` | 12 | 11917.582 | 1.03x | 8/12 | 7/7 | 1.000 | 1.000 |
| `nthu_fast_layer` | 12 | 7729.719 | 1.59x | 8/12 | 7/7 | 1.743 | 1.851 |
| `nthu_fast_layer_repair` | 12 | 10647.096 | 1.15x | 8/12 | 7/7 | 1.745 | 1.855 |
| `nthu_p2p3_budget` | 12 | 14772.150 | 0.83x | 4/12 | 4/7 | 1.764 | 1.891 |
| `nthu_p2p3_legal_repair` | 12 | 11451.116 | 1.07x | 8/12 | 7/7 | 1.743 | 1.851 |
| `nthu_cuda_score` | 12 | 12740.672 | 0.96x | 2/12 | 2/7 | 1.854 | 2.042 |
| `nthu_edgecount_post` | 12 | 2287.760 | 5.38x | 2/12 | 2/7 | 1.782 | 1.912 |

Interpretation:

- `OpenMP` 保持品質，但加速太小。
- `edgecount_post` 很快，但 legality 不夠，不能當 final legal router。
- 舊 `fast_layer` 類策略可以讓 original-legal 保持合法，但 WL 膨脹太大。
- 因此問題不是單純「能不能更快」，而是 fast layer 的品質和 budget 的 overflow 需要同時處理。

## 4. Compute Path And Utilization

三種 compute path 都被當作可能手段測過：單核演算法加速、多核/OpenMP、CUDA。
結論不是直接放棄多核或 CUDA，而是根據 utilization 判斷目前哪個方向真正有效。

### 4.1 Single-Core Algorithmic Path

目前 final result 主要靠單核演算法改動：

- `fast_layer_netguided_budget`
- `fast_layer_netguided_repair`

這些版本每個 testcase 仍是單一 `NthuRoute` process，但單 case runtime 下降。
VM final run 使用：

```text
MAX_ROUTER_CORES=12
PARALLEL_BENCH_JOBS=7
bench_count=7
run_variants=fast_layer_netguided_budget fast_layer_netguided_repair
```

也就是每個 testcase 用一個單核 router process，同時跑多個 testcase。這是目前最穩
的 CPU utilization 方式：不改 shared congestion map 的平行語意，避免 data race，
但能在 benchmark workflow 層使用多個核心。

### 4.2 Multi-Core / OpenMP Path

OpenMP 版本不是沒有啟動 threads，而是 end-to-end utilization 沒上去。

| Benchmark | Threads | Seconds | Avg process CPU | Avg live threads | Overflow |
| --- | ---: | ---: | ---: | ---: | ---: |
| newblue2 | 1 | 65.647 | 99.398% | 1.000 | 0 |
| newblue2 | 4 | 64.611 | 100.665% | 3.339 | 0 |
| newblue2 | 8 | 63.587 | 102.198% | 6.508 | 0 |
| newblue2 | 12 | 63.587 | 103.144% | 9.492 | 0 |
| adaptec3 | 1 | 491.501 | 99.840% | 1.000 | 0 |
| adaptec3 | 12 | 485.315 | 101.785% | 11.315 | 0 |

Profile breakdown shows why CPU stays near one effective core:

| Benchmark | Threads | `route_all` share | `specify_all_range` share of `route_all` |
| --- | ---: | ---: | ---: |
| newblue2 | 1 | 0.992426 | 0.989974 |
| newblue2 | 12 | 0.997441 | 0.991347 |
| adaptec3 | 1 | 0.998021 | 0.998154 |
| adaptec3 | 12 | 0.999589 | 0.998764 |

Interpretation:

- OpenMP worker threads exist, so this is not a launch/binding failure.
- The parallelized reductions/scans are too small.
- The bottleneck is still the sequential rip-up/reroute loop under
  `RangeRouter::range_router()` / `specify_all_range()`.
- Real per-testcase multicore speedup needs conflict-aware reroute batching:
  independent two-pin routes can be solved in parallel using a read-only congestion
  snapshot, then committed with legality checks.

Follow-up prototype:

| Prototype | Result on `newblue2` | Interpretation |
| --- | --- | --- |
| conflict-box parallel maze commit (`db540bb`) | `2609.637s`, aborted after first iteration | unsafe and too slow; shared route state/order still matters. |
| no-maze parallel + serial maze fallback (`a5465c9`) | `136.985s`, legal | uses more CPU but doubles runtime. |
| capped no-maze parallel (`e648e19`, cap 4096) | `80.255s`, legal | less bad but still slower than `65.739s` default. |
| capped no-maze parallel (`e648e19`, cap 512) | `90.646s`, legal | lower utilization and still slower. |

Conclusion: per-testcase multicore reroute was implemented behind
`NTHU_PARALLEL_REROUTE_BATCHES=1` and measured on the VM, but it should remain
opt-in only.  It increases CPU utilization, yet route-order changes cause more
iterations and serial maze fallback still dominates.  The production strategy should
keep OpenMP as a correct low-impact attempt and use multi-process parallel benchmark
execution for immediate CPU utilization.

### 4.3 CUDA Path

CUDA was tested as single GPU, dual-visible GPU, explicit dual-GPU preselect, and
two-process throughput.  All measured CUDA rows were legal, but utilization shows
the GPU work is too small relative to CPU routing.

| Scenario | Benchmark | Seconds | GPU0 avg/max util | GPU1 avg/max util | Result |
| --- | --- | ---: | ---: | ---: | --- |
| `single_costed` | adaptec3 | 194.907 | 0.122% / 8% | 0% / 0% | legal |
| `dual_visible_costed` | adaptec3 | 191.291 | 0.158% / 8% | 0% / 0% | legal |
| `single_preselect` | adaptec3 | 197.496 | 0.080% / 5% | 0% / 0% | legal |
| `dual_multigpu_preselect` | adaptec3 | 199.862 | 0.171% / 9% | 0% / 0% | legal |

CUDA profile counters on adaptec3:

| Scenario | `specify_all_range_ms` | `cuda_prepare_ms` | `cuda_maze_ms` |
| --- | ---: | ---: | ---: |
| `single_costed` | 54103.715 | 0.000 | 1068.330 |
| `dual_visible_costed` | 53158.383 | 0.000 | 861.536 |
| `single_preselect` | 55109.771 | 646.620 | 1044.491 |
| `dual_multigpu_preselect` | 54744.162 | 728.413 | 848.683 |

Interpretation:

- GPU kernels are correct but too fragmented.
- GPU average utilization is near zero because CUDA calls are short and separated by
  CPU sequential routing.
- Dual GPU does not help single-testcase latency; GPU1 stays effectively idle in
  current flow.
- Future CUDA work should batch many candidate evaluations or route boxes into larger
  GPU work units.  Simply exposing two GPUs is not enough.

## 5. Final Quality-Sensitive Result

Final selected version for original-legal cases:

- Use `fast_layer_netguided_budget` if it is already legal.
- Use `fast_layer_netguided_repair` when budget leaves overflow.
- Enforce `overflow=0,max_overflow=0`.
- Enforce selected wirelength `<= 1.5x original`.

| Benchmark | Selected version | Original s | Selected s | Speedup | WL ratio | OF / Max |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| adaptec1 | `fast_layer_netguided_budget` | 441.963 | 261.288 | 1.69x | 1.401 | 0 / 0 |
| adaptec3 | `fast_layer_netguided_budget` | 479.186 | 400.789 | 1.20x | 1.302 | 0 / 0 |
| adaptec4 | `fast_layer_netguided_budget` | 130.667 | 116.625 | 1.12x | 1.320 | 0 / 0 |
| adaptec5 | `fast_layer_netguided_repair` | 1240.592 | 854.320 | 1.45x | 1.350 | 0 / 0 |
| bigblue1 | `fast_layer_netguided_repair` | 1206.307 | 609.836 | 1.98x | 1.425 | 0 / 0 |
| newblue2 | `fast_layer_netguided_budget` | 76.516 | 54.345 | 1.41x | 1.417 | 0 / 0 |
| newblue6 | `fast_layer_netguided_repair` | 3278.214 | 1046.369 | 3.13x | 1.359 | 0 / 0 |

Legal7 aggregate:

| Metric | Original | Final selected | Difference |
| --- | ---: | ---: | ---: |
| Total runtime | 6853.445s | 3343.573s | 2.05x faster |
| Overflow | 0 on all 7 | 0 on all 7 | no legality regression |
| Average WL ratio | 1.000 | 1.368 | +36.8% WL |
| Worst WL ratio | 1.000 | 1.425 | <= 1.5x guard |

Compared with previous fastest guarded legal portfolio:

| Portfolio | Speedup | Avg WL ratio | Worst WL ratio |
| --- | ---: | ---: | ---: |
| Previous fastest guarded | 2.18x | 1.767 | 1.862 |
| Final net-guided WL guard | 2.05x | 1.368 | 1.425 |

The final version gives up a small amount of speed but substantially improves score
quality.  This is the best current answer for "wire length 不差太多且接近 2x speedup".

## 6. Overflow Repair Evidence

The faster net-guided budget version still caused overflow on three original-legal
large cases.  The repair version fixed those cases while keeping WL under `1.5x`.

| Benchmark | Budget OF / Max | Budget speedup | Budget WL ratio | Repair OF / Max | Repair speedup | Repair WL ratio |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| adaptec5 | 6 / 2 | 1.77x | 1.375 | 0 / 0 | 1.45x | 1.350 |
| bigblue1 | 156 / 4 | 2.25x | 1.455 | 0 / 0 | 1.98x | 1.425 |
| newblue6 | 152 / 8 | 2.97x | 1.374 | 0 / 0 | 3.13x | 1.359 |

This confirms the overflow issue was not in the verifier or output format.  It was
caused by aggressive routing budget ending before all congested areas were repaired.

## 7. Original-Overflow Cases

Some requested cases already overflow under original, so they cannot be used to prove
"no regression from legal to illegal".  For these, the speed-frontier strategy reduces
overflow dramatically but does not always reach zero.

| Benchmark | Original overflow | Fastest selected overflow | Speedup |
| --- | ---: | ---: | ---: |
| adaptec2 | 958172 | 866 | 3.35x |
| bigblue2 | 1928338 | 3004 | 7.33x |
| bigblue3 | 1724140 | 1536 | 7.50x |
| newblue1 | 839522 | 2368 | 23.57x |
| newblue5 | 3427158 | 1962 | 6.04x |

These rows are useful for speed and overflow-reduction claims, but not for strict
zero-overflow final claims.

## 8. Logical Problem Localization

| Observation | Hypothesis Tested | Evidence | Problem Section | Action |
| --- | --- | --- | --- | --- |
| OpenMP creates many threads but CPU stays near one effective core. | Maybe thread binding/cache placement is wrong. | `OMP_NUM_THREADS=12` still averaged about 100% CPU; profiling showed `specify_all_range()` dominates `route_all`. | `Range_router.cpp` / sequential rip-up-reroute mutation loop. | Do not spend more effort on small OpenMP reductions; real multicore needs conflict-aware reroute batching. |
| Fast strategies are legal but WL ratio becomes 1.7x-1.9x. | Maybe routing budget alone causes WL inflation. | Even legal fast layer variants had avg legal-case WL around 1.74x. | `Layerassignment.cpp`, original fast greedy chooses layer independently per edge. | Add net-guided layer assignment to keep a net close to one preferred layer. |
| Budget version is fast but some original-legal cases overflow. | Maybe verifier is too strict or output is malformed. | Budget rows had small but real verifier overflow on adaptec5/bigblue1/newblue6. Repair rows on same outputs/benchmarks fixed to zero. | `Construct_2d_tree.cpp` P2/P3 effort and post-processing budget. | Use budget as first attempt, then conservative repair fallback for illegal rows. |
| Edge-count post-processing is extremely fast. | Could be final router. | 12-case speedup `5.38x`, but only 2/12 legal and only 2/7 original-legal remain legal. | `Post_processing.cpp` candidate pruning too aggressive. | Keep as speed frontier / ablation, not final quality setting. |
| Dual GPU does not improve single-case runtime. | Maybe two V100s can halve CUDA time. | GPU1 utilization stayed 0 in single-process runs; CUDA work was only about one second inside ~195s adaptec3 run. | `CudaDogleg.cu` and CPU/GPU call granularity. | Use single GPU for latency; future work needs batched GPU work units. |

## 9. Final Conclusion

The bottleneck analysis shows that simple OpenMP does not solve the dominant sequential
rip-up/reroute loop, and the fastest CPU/GPU shortcuts can easily damage legality or
wirelength.  The final adopted solution is therefore a guarded portfolio:

1. Use net-guided fast layer assignment to reduce layer-assignment time without the
   old per-edge WL explosion.
2. Use faster P2/P3 budget when it is already legal.
3. Fall back to conservative repair when budget leaves overflow.
4. Enforce `overflow=0,max_overflow=0` and `WL<=1.5x original` on original-legal cases.

This produces `2.05x` aggregate speedup on all 7 original-legal cases while preserving
zero overflow and keeping worst wirelength ratio under `1.43x`.
