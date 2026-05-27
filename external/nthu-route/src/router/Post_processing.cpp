#include "Post_processing.h"

#include <algorithm>
#include <chrono>
#include <cstring>
#include <cstdio>
#include <cstdlib>
#include <tuple>
#include <unordered_map>
#include <utility>
#include <vector>

#include "../misc/geometry.h"
#include "Congestion.h"
#include "Construct_2d_tree.h"
#include "DataDef.h"
#include "parameter.h"
#include "Range_router.h"
#include "Route_2pinnets.h"
//#define SPDLOG_TRACE_ON
#include "../spdlog/spdlog.h"

namespace NTHUR {

namespace {

using ProfileClock = std::chrono::steady_clock;

double profile_ms(ProfileClock::time_point start, ProfileClock::time_point end) {
    return std::chrono::duration<double, std::milli>(end - start).count();
}

bool profile_enabled() {
    return std::getenv("NTHU_PROFILE") != nullptr;
}

bool post_reevaluate_cost_enabled() {
    return std::getenv("NTHU_POST_REEVALUATE_COST") != nullptr;
}

bool post_excess_edge_repair_enabled() {
    return std::getenv("NTHU_POST_EXCESS_EDGE_REPAIR") != nullptr;
}

bool post_excess_edge_repair_after_first_enabled() {
    return std::getenv("NTHU_POST_EXCESS_EDGE_REPAIR_AFTER_FIRST") != nullptr;
}

int env_int(const char* name, int default_value) {
    const char* value = std::getenv(name);
    if (value == nullptr || *value == '\0') {
        return default_value;
    }
    return std::atoi(value);
}

bool segments_near(const Coordinate_2d& a1, const Coordinate_2d& a2,
        const Coordinate_2d& b1, const Coordinate_2d& b2, int radius) {
    const int amin_x = std::min(a1.x, a2.x) - radius;
    const int amax_x = std::max(a1.x, a2.x) + radius;
    const int amin_y = std::min(a1.y, a2.y) - radius;
    const int amax_y = std::max(a1.y, a2.y) + radius;
    const int bmin_x = std::min(b1.x, b2.x);
    const int bmax_x = std::max(b1.x, b2.x);
    const int bmin_y = std::min(b1.y, b2.y);
    const int bmax_y = std::max(b1.y, b2.y);
    return amin_x <= bmax_x && bmin_x <= amax_x && amin_y <= bmax_y && bmin_y <= amax_y;
}

} // namespace

bool COUNTER::operator <(const COUNTER& o) const {
    return std::tie(total_overflow, bsize) < std::tie(o.total_overflow, o.bsize);

}

void Post_processing::initial_for_post_processing(int post_iteration) {
    const bool do_profile = profile_enabled();
    const auto profile_start = ProfileClock::now();

    vector<COUNTER> counter(construct_2d_tree.two_pin_list.size());
    std::vector<unsigned char> neighbor_candidate(construct_2d_tree.two_pin_list.size(), 0);
    std::vector<std::pair<Coordinate_2d, Coordinate_2d>> overflow_edges;
    const int neighbor_radius = env_int("NTHU_POST_NEIGHBOR_REPAIR_RADIUS", 0);
    if (neighbor_radius > 0) {
        const auto neighbor_start = ProfileClock::now();
        const int x_size = congestion.congestionMap2d.getXSize();
        const int y_size = congestion.congestionMap2d.getYSize();
        for (int x = 0; x < x_size; ++x) {
            for (int y = 0; y < y_size; ++y) {
                const Coordinate_2d c { x, y };
                if (x + 1 < x_size) {
                    const Coordinate_2d n { x + 1, y };
                    if (congestion.congestionMap2d.edge(c, n).isOverflow()) {
                        overflow_edges.emplace_back(c, n);
                    }
                }
                if (y + 1 < y_size) {
                    const Coordinate_2d n { x, y + 1 };
                    if (congestion.congestionMap2d.edge(c, n).isOverflow()) {
                        overflow_edges.emplace_back(c, n);
                    }
                }
            }
        }
        if (do_profile) {
            log_sp->info("profile post neighbor_scan_ms={:.3f} overflow_edges={}",
                    profile_ms(neighbor_start, ProfileClock::now()), overflow_edges.size());
        }
    }
    const int pin_count = static_cast<int>(construct_2d_tree.two_pin_list.size());
    int overflow_seen = 0;

    const auto counter_start = ProfileClock::now();
#ifdef NTHU_ROUTE_OPENMP
#pragma omp parallel for schedule(dynamic, 128) reduction(max:overflow_seen)
#endif
    for (int i = pin_count - 1; i >= 0; --i) {

        Two_pin_element_2d& twopList = construct_2d_tree.two_pin_list[i];

        counter[i].id = i;
        counter[i].total_overflow = 0;
        counter[i].max_overflow_edge = 0;
        counter[i].overflow_edge_count = 0;
        counter[i].bsize = abs(twopList.pin1.x - twopList.pin2.x) + abs(twopList.pin1.y - twopList.pin2.y);
        for (int j = twopList.path.size() - 1; j > 0; --j) {

            Edge_2d& edge = congestion.congestionMap2d.edge(twopList.path[j - 1], twopList.path[j]);
            if (edge.isOverflow()) {
                const int overuse = max(0, edge.overUsage());
                counter[i].total_overflow += overuse;
                counter[i].max_overflow_edge = std::max(counter[i].max_overflow_edge, overuse);
                ++counter[i].overflow_edge_count;
            }
        }
        if (counter[i].total_overflow > 0) {
            overflow_seen = 1;
        } else if (!overflow_edges.empty()) {
            for (int j = static_cast<int>(twopList.path.size()) - 1; j > 0 && !neighbor_candidate[i]; --j) {
                for (const auto& overflow_edge : overflow_edges) {
                    if (segments_near(twopList.path[j - 1], twopList.path[j],
                                overflow_edge.first, overflow_edge.second, neighbor_radius)) {
                        neighbor_candidate[i] = 1;
                        break;
                    }
                }
            }
        }
    }
    const double counter_ms = profile_ms(counter_start, ProfileClock::now());

    total_no_overflow = (overflow_seen == 0);

    if (total_no_overflow) {
        if (do_profile) {
            log_sp->info("profile post initial_for_post_processing counter_ms={:.3f} sort_ms=0.000 reroute_ms=0.000 total_ms={:.3f} candidates=0",
                    counter_ms, profile_ms(profile_start, ProfileClock::now()));
        }
        return;
    }

    std::vector<unsigned char> excess_edge_candidate;
    int excess_edge_selected = 0;
    int excess_edge_entries = 0;
    const auto excess_start = ProfileClock::now();
    const bool use_excess_edge_repair =
            post_excess_edge_repair_enabled() ||
            (post_iteration > 1 && post_excess_edge_repair_after_first_enabled());
    if (use_excess_edge_repair) {
        struct EdgeCandidate {
            int id;
            int score;
            int bsize;
        };
        std::unordered_map<const Edge_2d*, std::vector<EdgeCandidate>> edge_candidates;
        edge_candidates.reserve(4096);
        for (int i = 0; i < pin_count; ++i) {
            if (counter[i].total_overflow <= 0) {
                continue;
            }
            const Two_pin_element_2d& twopList = construct_2d_tree.two_pin_list[i];
            for (int j = static_cast<int>(twopList.path.size()) - 1; j > 0; --j) {
                const Edge_2d& edge = congestion.congestionMap2d.edge(twopList.path[j - 1], twopList.path[j]);
                if (edge.isOverflow()) {
                    edge_candidates[&edge].push_back(EdgeCandidate { i, counter[i].total_overflow, counter[i].bsize });
                    ++excess_edge_entries;
                }
            }
        }

        excess_edge_candidate.assign(pin_count, 0);
        const int mult = std::max(1, env_int("NTHU_POST_EXCESS_EDGE_REPAIR_MULT", 1));
        for (auto& item : edge_candidates) {
            const Edge_2d* edge = item.first;
            std::vector<EdgeCandidate>& candidates = item.second;
            std::sort(candidates.begin(), candidates.end(), [](const EdgeCandidate& a, const EdgeCandidate& b) {
                if (a.score != b.score) {
                    return a.score > b.score;
                }
                return a.bsize > b.bsize;
            });
            const int pick_count = std::min(static_cast<int>(candidates.size()),
                    std::max(1, edge->overUsage() * mult));
            for (int i = 0; i < pick_count; ++i) {
                if (!excess_edge_candidate[candidates[i].id]) {
                    excess_edge_candidate[candidates[i].id] = 1;
                    ++excess_edge_selected;
                }
            }
        }
        log_sp->info("post excess edge repair: iteration={} overflow_edges={} entries={} selected={} mult={}",
                post_iteration, edge_candidates.size(), excess_edge_entries, excess_edge_selected, mult);
    }
    const double excess_ms = profile_ms(excess_start, ProfileClock::now());

    const auto sort_start = ProfileClock::now();
    const char* post_sort_mode = std::getenv("NTHU_POST_SORT_MODE");
    if (post_sort_mode != nullptr && std::strcmp(post_sort_mode, "short_first") == 0) {
        std::sort(counter.begin(), counter.end(), [](const COUNTER& a, const COUNTER& b) {
            if (a.total_overflow != b.total_overflow) {
                return a.total_overflow > b.total_overflow;
            }
            return a.bsize < b.bsize;
        });
    } else if (post_sort_mode != nullptr && std::strcmp(post_sort_mode, "max_edge") == 0) {
        std::sort(counter.begin(), counter.end(), [](const COUNTER& a, const COUNTER& b) {
            if (a.max_overflow_edge != b.max_overflow_edge) {
                return a.max_overflow_edge > b.max_overflow_edge;
            }
            if (a.total_overflow != b.total_overflow) {
                return a.total_overflow > b.total_overflow;
            }
            return a.bsize < b.bsize;
        });
    } else if (post_sort_mode != nullptr && std::strcmp(post_sort_mode, "edge_count") == 0) {
        std::sort(counter.begin(), counter.end(), [](const COUNTER& a, const COUNTER& b) {
            if (a.overflow_edge_count != b.overflow_edge_count) {
                return a.overflow_edge_count > b.overflow_edge_count;
            }
            if (a.max_overflow_edge != b.max_overflow_edge) {
                return a.max_overflow_edge > b.max_overflow_edge;
            }
            if (a.total_overflow != b.total_overflow) {
                return a.total_overflow > b.total_overflow;
            }
            return a.bsize < b.bsize;
        });
    } else if (post_sort_mode != nullptr && std::strcmp(post_sort_mode, "max_edge_short") == 0) {
        std::sort(counter.begin(), counter.end(), [](const COUNTER& a, const COUNTER& b) {
            if (a.max_overflow_edge != b.max_overflow_edge) {
                return a.max_overflow_edge > b.max_overflow_edge;
            }
            if (a.bsize != b.bsize) {
                return a.bsize < b.bsize;
            }
            return a.total_overflow > b.total_overflow;
        });
    } else if (post_sort_mode != nullptr && std::strcmp(post_sort_mode, "density") == 0) {
        std::sort(counter.begin(), counter.end(), [](const COUNTER& a, const COUNTER& b) {
            const double a_density = a.total_overflow / std::max(1, a.bsize);
            const double b_density = b.total_overflow / std::max(1, b.bsize);
            if (a_density != b_density) {
                return a_density > b_density;
            }
            if (a.total_overflow != b.total_overflow) {
                return a.total_overflow > b.total_overflow;
            }
            return a.bsize < b.bsize;
        });
    } else if (post_sort_mode != nullptr && std::strcmp(post_sort_mode, "impact") == 0) {
        std::sort(counter.begin(), counter.end(), [](const COUNTER& a, const COUNTER& b) {
            const double a_impact = a.total_overflow * std::max(1, a.max_overflow_edge);
            const double b_impact = b.total_overflow * std::max(1, b.max_overflow_edge);
            if (a_impact != b_impact) {
                return a_impact > b_impact;
            }
            if (a.overflow_edge_count != b.overflow_edge_count) {
                return a.overflow_edge_count > b.overflow_edge_count;
            }
            return a.bsize < b.bsize;
        });
    } else if (post_sort_mode != nullptr && std::strcmp(post_sort_mode, "hot_density") == 0) {
        std::sort(counter.begin(), counter.end(), [](const COUNTER& a, const COUNTER& b) {
            const double a_density = (a.total_overflow * std::max(1, a.max_overflow_edge)) / std::max(1, a.bsize);
            const double b_density = (b.total_overflow * std::max(1, b.max_overflow_edge)) / std::max(1, b.bsize);
            if (a_density != b_density) {
                return a_density > b_density;
            }
            if (a.total_overflow != b.total_overflow) {
                return a.total_overflow > b.total_overflow;
            }
            return a.bsize < b.bsize;
        });
    } else {
        std::sort(counter.begin(), counter.end(), [&](COUNTER& a,COUNTER& b ) {return b< a;});	// sort by flag
    }
    const double sort_ms = profile_ms(sort_start, ProfileClock::now());
    if (post_sort_mode != nullptr && *post_sort_mode != '\0') {
        log_sp->info("post sort mode: {}", post_sort_mode);
    }

    int post_overflow_limit = env_int("NTHU_POST_OVERFLOW_LIMIT", 0);
    const int post_overflow_limit_after_first = env_int("NTHU_POST_OVERFLOW_LIMIT_AFTER_FIRST", 0);
    if (post_overflow_limit_after_first > 0) {
        post_overflow_limit = post_iteration <= 1 ? 0 : post_overflow_limit_after_first;
    }
    int post_min_score = env_int("NTHU_POST_MIN_OVERFLOW_SCORE", 0);
    const int post_min_score_after_first = env_int("NTHU_POST_MIN_OVERFLOW_SCORE_AFTER_FIRST", 0);
    if (post_min_score_after_first > 0) {
        post_min_score = post_iteration <= 1 ? 0 : post_min_score_after_first;
    }
    int routed_overflow_candidates = 0;
    int skipped_low_score_candidates = 0;

    // According other attribute to do maze routing
    const auto reroute_start = ProfileClock::now();
    for (int i = 0; i < pin_count; ++i) {
        int id = counter[i].id;
        Two_pin_element_2d& twopList = construct_2d_tree.two_pin_list[id];
        // call maze routing
        if (counter[i].total_overflow > 0) {
            if (!excess_edge_candidate.empty() && !excess_edge_candidate[id]) {
                continue;
            }
            if (post_overflow_limit > 0 && routed_overflow_candidates >= post_overflow_limit) {
                continue;
            }
            if (post_min_score > 0 && counter[i].total_overflow < post_min_score) {
                ++skipped_low_score_candidates;
                continue;
            }
            ++routed_overflow_candidates;
            rangeRouter.range_router(twopList, 3);
        } else if (neighbor_candidate[id]) {
            rangeRouter.range_router(twopList, 3);
        }
    }
    const double reroute_ms = profile_ms(reroute_start, ProfileClock::now());
    if (post_overflow_limit > 0) {
        log_sp->info("post overflow candidate limit: routed={} limit={}", routed_overflow_candidates, post_overflow_limit);
    }
    if (post_min_score > 0) {
        log_sp->info("post overflow score gate: routed={} min_score={} skipped_low_score={}",
                routed_overflow_candidates, post_min_score, skipped_low_score_candidates);
    }
    if (do_profile) {
        log_sp->info("profile post initial_for_post_processing counter_ms={:.3f} excess_ms={:.3f} sort_ms={:.3f} reroute_ms={:.3f} total_ms={:.3f} candidates={} skipped_low_score={} excess_selected={} excess_entries={}",
                counter_ms, excess_ms, sort_ms, reroute_ms, profile_ms(profile_start, ProfileClock::now()),
                routed_overflow_candidates, skipped_low_score_candidates, excess_edge_selected, excess_edge_entries);
    }

}

Post_processing::Post_processing(const RoutingParameters& routingparam, Congestion& congestion, Construct_2d_tree& construct_2d_tree, RangeRouter& rangeRouter) :
        routing_parameter { routingparam },	//
        congestion { congestion },	//
        total_no_overflow { false },	//
        construct_2d_tree { construct_2d_tree }, //
        rangeRouter { rangeRouter } {

    log_sp = spdlog::get("NTHUR");
}

void Post_processing::process(Route_2pinnets& route_2pinnets) {
    const bool do_profile = profile_enabled();
    const auto post_start = ProfileClock::now();

    log_sp->info("================================================================");
    log_sp->info("===                   Enter Post Processing                  ===");
    log_sp->info("================================================================");

    int Post_processing_iteration = routing_parameter.get_iteration_p3();

    construct_2d_tree.BOXSIZE_INC = routing_parameter.get_init_box_size_p3();
    int inc_num = routing_parameter.get_box_size_inc_p3();
    SPDLOG_TRACE(log_sp, "size: ({} {}) ", construct_2d_tree.BOXSIZE_INC, inc_num);

    construct_2d_tree.done_iter++;
    congestion.used_cost_flag = MADEOF_COST;
    int cur_overflow = congestion.cal_max_overflow();
    if (cur_overflow > 0) {
        //In post processing, we only need to pre-evaluate all cost once.
        //The other update will be done by update_add(remove)_edge
        congestion.pre_evaluate_congestion_cost();
        for (int i = 0; i < Post_processing_iteration; ++i, ++construct_2d_tree.done_iter) {
            log_sp->info(" Iteration:  {}", i + 1);
            if (i > 0 && post_reevaluate_cost_enabled()) {
                congestion.pre_evaluate_congestion_cost();
            }

            total_no_overflow = true;

            const auto iter_start = ProfileClock::now();
            initial_for_post_processing(i + 1);

            auto phase_start = ProfileClock::now();
            cur_overflow = congestion.cal_max_overflow();
            const double overflow_ms = profile_ms(phase_start, ProfileClock::now());
            phase_start = ProfileClock::now();
            congestion.cal_total_wirelength();
            const double wirelength_ms = profile_ms(phase_start, ProfileClock::now());

            if (total_no_overflow || cur_overflow == 0) {
                if (do_profile) {
                    log_sp->info("profile post iter={} overflow_ms={:.3f} wirelength_ms={:.3f} reallocate_ms=0.000 clear_ms=0.000 total_ms={:.3f}",
                            i + 1, overflow_ms, wirelength_ms, profile_ms(iter_start, ProfileClock::now()));
                }
                break;
}
            construct_2d_tree.BOXSIZE_INC += inc_num;
            phase_start = ProfileClock::now();
            route_2pinnets.reallocate_two_pin_list();
            const double reallocate_ms = profile_ms(phase_start, ProfileClock::now());
            phase_start = ProfileClock::now();
            construct_2d_tree.mazeroute_in_range.clear_net_tree();
            const double clear_ms = profile_ms(phase_start, ProfileClock::now());
            if (do_profile) {
                log_sp->info("profile post iter={} overflow_ms={:.3f} wirelength_ms={:.3f} reallocate_ms={:.3f} clear_ms={:.3f} total_ms={:.3f}",
                        i + 1, overflow_ms, wirelength_ms, reallocate_ms, clear_ms, profile_ms(iter_start, ProfileClock::now()));
            }
        }
    }
    log_sp->info("maze routing complete successfully");
    if (do_profile) {
        log_sp->info("profile post total_ms={:.3f}", profile_ms(post_start, ProfileClock::now()));
    }

}

} // namespace NTHUR
