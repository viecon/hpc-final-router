# Optimization Methods, Commits, WL, and Speed Summary

Date: 2026-06-05
Branch: `vm-fastest-benchmark-guard`

## Reading Notes

- All benchmark numbers below come from existing VM reports/docs.  No new
  benchmark was run for this summary.
- "Speedup" uses the denominator stated in the source report.  Most rows compare
  against `external/nthu-route-original`; `main_vs_current` compares against
  `origin/main` under the same CLI budget.
- WL is reported as ratio when the report has enough original/optimized WL data.
  "Avg" and "worst" usually refer to the cases in that report scope.
- Code commits without their own benchmark table are tied to the next report that
  validates or rejects the method.

## Method Family Summary

| Method family | Main commits / reports | Optimization idea | Best speed result | WL impact | Correctness / decision |
| --- | --- | --- | ---: | --- | --- |
| OpenMP analysis kernels | `../docs/10-early-source-strategy-report.md`, `../docs/20-vm-optimization-version-matrix.md`, `../docs/21-vm-multicore-utilization-log.md` | Parallelize congestion scans, overflow/WL reductions, interval setup, candidate counters. | 12-case `nthu_openmp_t4`: `1.03x`; adaptec1-3: `1.009x`. | About `1.000x`; no WL regression. | Correct but too small. Profiling showed `specify_all_range()` / sequential reroute still dominates. |
| Conflict-aware multicore reroute prototype | `db540bb`, `a5465c9`, `e648e19`, `../docs/21-vm-multicore-utilization-log.md` | Batch non-overlapping two-pin reroutes, use local scratch, serialize unsafe maze fallback. | None. On `newblue2`, default `65.739s`; capped prototype `80.255s`. | Similar WL on `newblue2` around `7.59M`. | More CPU utilization but slower. Kept opt-in only. |
| Fast greedy layer assignment | early docs, `../docs/20-vm-optimization-version-matrix.md` | Replace expensive KLAT/DP layer assignment with greedy projected-demand layer choice. | 12-case `1.59x`; adaptec1-3 representative legal rows around `1.8x-2.1x`. | Legal-case avg WL ratio about `1.743`, worst `1.851`. | Useful speed path, but WL too inflated for final quality. |
| Net-guided / low-layer fast assignment | `7ac91ce`, `7300fb7`, `53b1965`, `../docs/23-wl-guard-speedup.md`, `../docs/24-wl120-single-core-results.md` | Give each net a preferred layer and prefer low legal layers before congested fallback. | Legal7 WL<=1.5 portfolio: `2.05x`; WL<=1.2 portfolio: `1.961x`. | WL<=1.5 avg/worst `1.368/1.425`; WL<=1.2 avg/worst `1.125/1.163`. | Selected direction for WL control. The 3.585x WL<=1.2 speed frontier was illegal. |
| P2/P3 budget tuning | early docs, `../docs/10-early-source-strategy-report.md`, `../docs/12-early-vm-speed-frontier.md` | Reduce routing effort via P2/P3 iteration, threshold, box-size tuning. | Best legal adaptec1: `2.118x`; fastest guarded 12-case portfolio: `3.17x`. | Fastest guarded original-legal avg/worst WL `1.767/1.862`. | Strong speed lever, but fixed budget is not stable enough without repair. |
| Edge-count post-processing | `../docs/10-early-source-strategy-report.md`, `../docs/20-vm-optimization-version-matrix.md` | Sort post-processing candidates by overflow edge count and prune reroutes. | 12-case `5.38x`; 16-case median `4.331x`; newblue1 frontier `21.300x`. | Often high, all-case avg around `1.8x+` in guarded tables. | Runtime frontier only. Legal coverage was poor, e.g. `2/12` or `2/7`. |
| CUDA costed maze / dogleg scoring | CUDA commits, `../docs/22-vm-cuda-utilization-log.md`, `../docs/10-early-source-strategy-report.md` | GPU candidate / bounded maze scoring, single and dual GPU probes. | Standalone scorer `33x-38x`; integrated legal adaptec3 `2.780x`. | Often high in early legal rows, e.g. adaptec3 about `1.706x` vs original WL. | Correct on selected rows, but end-to-end GPU utilization near zero. Dual GPU did not improve latency. |
| Overall adaptive legal repair | `db48d4a`, `ce04c6d`, `0f7103a`, `b982db4` | One global strategy: short initial P3, measure overflow, continue P2/P3 only if needed. | Legal7 `1.771x`; requested12 original-legal subset `1.597x`. | Legal7 avg/worst WL `1.116/1.151`. | Correct and no testcase-name hardcoding, but requested12 all-case runtime was only `0.922x`. |
| High-overflow adaptive P2 budget | `67c56da`, `e27cfab`, `9c10d52`, `d1b7584`, `03-final-vm-strategy-results.md` | If repair-entry overflow is high, raise P2 max to 24; cap small-overflow repair. | Requested12 `1.345x`; legal7 `1.752x`. | Requested12 avg/worst WL `1.158/1.284`; legal7 avg/worst `1.118/1.151`. | Current selected overall strategy before later probes. Legal `10/12`, original-legal guard `7/7`, total overflow `166`. |
| Strict legal maze fallback | `643aff2`, `fc65ece`, `9c10d52` | Try strict-capacity legal maze reroute behind env/phase/iteration gates. | No selected speed win. | Intended to reduce overflow without WL blowup. | Rejected: slower plateau; post-accept variant crashed during tree rebuild. |
| Layer-penalty probe | `7499b1f`, `05-wl-speed-literature-and-probes.md` | Tune net-guided layer penalties to reduce WL/overflow. | 4-case probe total `3104.704s` vs final `3106.744s`. | No WL change; probe/final WL ratio `1.000` on all 4 cases. | Negative result. Layer-score knobs were not the remaining bottleneck. |
| Bounded-length reroute guard | `de271c9`, `5b0fea5`, `f13c7d6`, `06-bounded-length-reroute-probe.md` | Limit over-length maze reroutes to reduce detours. First version rolled back externally; safe version rejects before tree mutation. | Not selected. Safe A2 was `2.557x` slower than final; safe A4 `6.039x` slower. | Slight WL reduction on A2/A4: A2 `5759135 -> 5750722`; A4 `13544728 -> 13525365`. | Unsafe version failed `12/12`; safe version correct on crash repros but too slow. Kept opt-in, disabled in final strategy. |

## Chronological Report / Commit Results

| Source | Related commit(s) | What changed | Scope | Speed | WL | Legality / overflow | Decision |
| --- | --- | --- | --- | ---: | --- | --- | --- |
| `../docs/11-early-results-summary.md` and `../docs/10-early-source-strategy-report.md` | early source-code strategies | Best-per-benchmark NTHU legal combination using P2/P3 tuning, fast layer, CUDA scoring. | adaptec1-3 | `2.325883x` legal NTHU speedup. | Computed from listed WL: avg about `1.514x`, worst about `1.758x`. | `overflow=0` on the selected 3 rows. | Good early claim, but not one universal strategy and WL can be high. |
| `../docs/12-early-vm-speed-frontier.md` | around `58cc00f` | Fastest guarded portfolio: choose fastest optimized row while preserving legality on original-legal cases. | requested 12 | `3.17x` aggregate. | All-case avg/worst WL `1.849/2.274`; original-legal avg/worst `1.767/1.862`. | Original-legal guard `7/7`; original-overflow cases still have residual overflow. | Strong speed frontier, too much WL for score-sensitive final. |
| `../docs/23-wl-guard-speedup.md` | `69f3eb7` | Net-guided fast greedy layer assignment. | original-legal 7 | `2.05x`. | Avg/worst WL `1.368/1.425`. | `7/7` zero overflow. | Better WL than fastest guarded portfolio, but still above 1.2x. |
| `../docs/24-wl120-single-core-results.md` | `7300fb7`, `53b1965` | Low-layer-first net-guided assignment plus legal repair portfolio. | original-legal 7 | `1.961x`. | Avg/worst WL `1.125/1.163`. | `7/7` zero overflow. | Meets WL<=1.2 and legality; misses requested 2.8x-3.2x speed. |
| `../docs/24-wl120-single-core-results.md` speed frontier | `7300fb7`, `53b1965` | Same WL<=1.2 direction but weakened repair. | original-legal 7 | `3.585x`. | Avg WL `1.138`, worst within 1.2. | Total overflow `13642`. | Shows speed target is reachable only by breaking legality. |
| `../docs/25-overall-adaptive-router-results.md` | `db48d4a`, `ce04c6d`, `0f7103a`, `b982db4` | One overall adaptive strategy, no benchmark-name selection. | legal7 | `1.771x`. | Avg/worst WL `1.116/1.151`. | `7/7` zero overflow. | Correct architecture, speed still short of target. |
| `../docs/25-overall-adaptive-router-results.md` requested12 | same | Same single strategy on requested 12. | requested 12 | all12 `0.922x`; original-legal subset `1.597x`. | `10/12` within WL<=1.2; legal7 all pass. | `8/12` legal. | Needed stronger hard-case repair. |
| `03-final-vm-strategy-results.md` | `67c56da`, `e27cfab`, `9c10d52`, `d1b7584` | Added high-overflow adaptive P2 max-iter 24 and small-overflow cap. | legal7 | `1.752x`. | Avg/worst WL `1.118/1.151`. | `7/7` zero overflow. | Selected for legal7 guard. |
| `03-final-vm-strategy-results.md` | same | Same final strategy on requested 12. | requested 12 | `1.345x`. | Avg/worst WL `1.158/1.284`. | `10/12` legal; total overflow `166`; original-legal guard `7/7`. | Best one-strategy result in that round. |
| `04-main-vs-final-router-comparison.md` | `3ae6b79`, compares `main` `6f44073` vs current `d1b7584` | Deep comparison of current adaptive strategy against main under same CLI. | requested 12 | current/main `1.677x`. | Avg/worst current/main WL `1.200/1.399`; same-CLI main-legal subset avg/worst `1.118/1.149`. | Main legal `4/12`; current legal `10/12`; total overflow `20851542 -> 166`. | Demonstrates current is faster and much more legal than same-CLI main. |
| `05-wl-speed-literature-and-probes.md` | `7499b1f` | Literature review plus stronger layer-penalty probe. | A1, A3, B2, N1 | Probe total `3104.704s`; final recheck `3106.744s`. | No WL change on all 4 rows. | Overflow unchanged: final/probe total `166`. | Rejected; remaining issue is 2D detour/repair schedule, not layer penalty. |
| `06-bounded-length-reroute-probe.md` unsafe run | `de271c9` | External rollback after over-length reroute. | requested 12 | All rows failed early. | No valid WL. | `12/12 fail`, representative `vector::_M_range_check` crash. | Rejected and root-caused to tree mutation rollback bug. |
| `06-bounded-length-reroute-probe.md` safe smoke | `5b0fea5` | Pass path-length bound into `MM_mazeroute` and reject before `adjust_twopin_element()`. | A2, A4 smoke | A2 `740.369s` vs final `289.548s`; A4 `781.975s` vs final `129.473s`. | Slightly better WL: A2 `0.999x` of final, A4 `0.999x` of final. | Both smoke cases legal `0/0`. | Correct but too slow; not enabled. |
| `06-bounded-length-reroute-probe.md` final recheck | `f13c7d6` report, final strategy still bounded off | Re-ran selected final env after bounded probe. | requested 12 | `1.294x` vs original; original-legal subset `1.687x`. | Same WL ratios as selected final family: all-case avg/worst `1.158/1.284`; legal7 avg/worst `1.118/1.151`. | `10/12` legal, total overflow `166`, original-legal guard `7/7`. | Final state after latest probe; bounded remains off. |

## Commit-To-Method Map

| Commit | Role | Metric source |
| --- | --- | --- |
| `6408778` | Documented OpenMP/CUDA utilization issue. | `../docs/20-vm-optimization-version-matrix.md`, `../docs/21-vm-multicore-utilization-log.md`, `../docs/22-vm-cuda-utilization-log.md`. |
| `db540bb` | First conflict-safe parallel reroute batch prototype. | Multicore log: raised CPU but `newblue2` took `2609.637s` and aborted after first iteration. |
| `a5465c9` | Serial maze fallback for parallel reroute. | Multicore log: `newblue2` legal but `136.985s`, slower than default `65.739s`. |
| `e648e19` | Cap parallel reroute candidates. | Multicore log: best capped `newblue2` row `80.255s`, still slower. |
| `7ac91ce` | Exposed net-guided layer WL penalty knobs. | Later layer-penalty probe showed no WL/overflow change. |
| `7300fb7` | Added low-layer net-guided fast assignment. | WL<=1.2 report: legal7 `1.961x`, avg/worst WL `1.125/1.163`. |
| `db48d4a` | Added overflow-triggered adaptive legal repair. | Overall adaptive report. |
| `ce04c6d` | Made post-processing budget adaptive. | Overall adaptive report. |
| `0f7103a` | Continued adaptive repair from completed P2 iteration. | Overall adaptive report: legal7 `1.771x`, avg/worst WL `1.116/1.151`. |
| `43b6488`, `7b4d038`, `7df3b08`, `7318914` | Added post-only repair gate, optional layer overflow repair, small-overflow cap, full remainder fallback. | Folded into VM optimization sweeps; not all selected. |
| `e27cfab` | Added post-processing stall stop guard. | VM optimization report: not selected; P2=24 did better. |
| `67c56da` | Added high-overflow adaptive P2 budget. | VM optimization report: requested12 `1.345x`, total overflow `166`. |
| `643aff2`, `fc65ece`, `9c10d52` | Strict legal maze fallback, same-net-cycle fix, iteration gate. | VM optimization report: slower/unstable, left disabled. |
| `d1b7584` | Updated final VM report with high-overflow repair results. | `03-final-vm-strategy-results.md`. |
| `3ae6b79` | Added main-vs-current comparison report. | `04-main-vs-final-router-comparison.md`. |
| `7499b1f` | Recorded final method review and WL-speed literature check. | `05-wl-speed-literature-and-probes.md`. |
| `de271c9` | Added opt-in bounded-length reroute guard. | Bounded report: unsafe rollback failed `12/12`. |
| `5b0fea5` | Made bounded-length maze rejection tree-safe. | Bounded report: safe on A2/A4 but too slow. |
| `f13c7d6` | Recorded bounded-length reroute probe. | This is the latest pushed report commit. |

## Current Best Interpretation

The useful optimizations are the ones that change routing effort and layer
assignment policy, not raw thread count:

1. Fast greedy layer assignment creates the largest legal speed gains, but plain
   fast layer inflates WL too much.
2. Net-guided low-layer assignment fixes much of the WL problem.
3. Adaptive legal repair and high-overflow P2 budget preserve original-legal
   correctness and reduce hard-case overflow without benchmark-name hardcoding.
4. OpenMP and CUDA are correct experiments but do not currently move end-to-end
   runtime because the dominant rip-up/reroute loop remains sequential.
5. Edge-count and weakened repair prove high speed is possible, but legality
   fails, so they are only frontier/ablation evidence.

The latest defensible one-strategy result is still the high-overflow adaptive
strategy with bounded-length disabled:

- requested12 speedup vs original: about `1.29x-1.35x` depending on rerun,
- original-legal subset speedup: about `1.69x-1.75x`,
- original-legal correctness: `7/7`,
- requested12 legality: `10/12`,
- requested12 WL avg/worst ratio: `1.158/1.284`.
