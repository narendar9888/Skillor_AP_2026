# Query Timings — Skillor

**File:** `05_query_timings.md`  
**Project:** Skillor — Skill Exchange Platform  
**Database:** PostgreSQL 16.15 on aarch64-apple-darwin25.6.0 (Apple Silicon)  
**Source queries:** `04_queries.sql` (Q1-Q45)  
**Benchmark dataset:** `plans/seed_data.sql`  
**Execution plans:** [`plans/`](plans/) — one file per query section

---

## 1. What This Document Measures

`04_queries.sql` defines 45 SQL queries across 9 sections. This document answers three questions about them: **how fast do they actually run** on a realistic dataset (measured across three consecutive runs and averaged), **which plan does the PostgreSQL planner choose for each one**, and **which of the indexes declared in `03_schema.sql` the planner really uses**. Every measurement comes from a real `EXPLAIN (ANALYZE, BUFFERS)` execution — no estimated costs — and the unabridged plan structure for all 45 queries is documented in the [`plans/`](plans/) folder, one file per section.

## 2. Benchmark Environment and Methodology

| Item | Value |
|---|---|
| PostgreSQL version | 16.15 (Homebrew, aarch64-apple-darwin25.6.0) |
| Tool | `EXPLAIN (ANALYZE, BUFFERS)`, text output |
| Dataset | `plans/seed_data.sql` — deterministic, fixed RNG seed |
| Passes | 1 cache-warmup pass + **3 measured runs (`Run 1`, `Run 2`, `Run 3`)**; **`Average (ms)`** reported |
| Transaction policy | one transaction per pass, **ROLLBACK** afterwards (Q37-Q45 leave no trace) |
| Statistics | `ANALYZE` run after seeding and between passes |
| Buffers | entire dataset resident in shared buffers during measurement |
| Hardware | local Apple Silicon macOS host — absolute numbers are indicative; relative comparisons are meaningful |

Each query from `04_queries.sql` was executed in one warmup pass followed by three measured passes (`Run 1`, `Run 2`, `Run 3`) against the seeded dataset, captured with `EXPLAIN (ANALYZE, BUFFERS)`. The `Average (ms)` column reports the arithmetic mean of `Run 1`, `Run 2`, and `Run 3` execution times (and `Planning (ms)` reports the 3-run mean planning time). Every pass ran inside a single transaction that was **rolled back** afterwards, so the INSERT/UPDATE/DELETE queries (Q37-Q45) left the seeded dataset untouched, and `ANALYZE` refreshed planner statistics between passes. Note that the unabridged single-pass plans archived in `plans/` were originally captured on PostgreSQL 16.2 (x86_64); every query produces the identical top-level plan node and row count on PostgreSQL 16.15.


### Document map

| Section of 04_queries.sql | Plan file | Queries |
|---|---|---|
| 1 — Basic SELECT | `plans/01_basic_select_queries.md` | Q1-Q8 |
| 2 — WHERE, ORDER BY, DISTINCT | `plans/02_where_order_by_distinct.md` | Q9-Q12 |
| 3 — JOIN | `plans/03_join_queries.md` | Q13-Q21 |
| 4 — Aggregates | `plans/04_aggregate_functions.md` | Q22-Q30 |
| 5 — GROUP BY / HAVING | `plans/05_group_by_having.md` | Q31-Q32 |
| 6 — Subqueries | `plans/06_subqueries.md` | Q33-Q36 |
| 7 — INSERT | `plans/07_insert_queries.md` | Q37-Q39 |
| 8 — UPDATE | `plans/08_update_queries.md` | Q40-Q43 |
| 9 — DELETE | `plans/09_delete_queries.md` | Q44-Q45 |

## 3. Dataset Overview

The benchmark runs on `seed_data.sql`, a deterministic dataset sized to match a platform with a few hundred active members. Row counts at measurement time:

| Table | Rows |
|---|---|
| users | 200 |
| skills | 60 |
| user_skills | 815 |
| matches | 300 |
| exchange_requests | 297 |
| conversations | 233 |
| messages | 3019 |
| reviews | 358 |
| notifications | 1002 |
| **Total** | **6284** |

Several seed constraints exist purely so the DML queries (Q37-Q45) can execute without violating schema constraints: the skill 'JavaScript' is deliberately absent (Q37 inserts it), user 1 never teaches skill 1 or learns skill 2 (Q38/Q39 insert those), exchange request #1 is pending (Q41 accepts it), and message #1 and notification #1 are unread (Q42/Q43 mark them read; Q45 deletes notification #1). Because each pass runs in a single transaction that is rolled back afterwards (and Q44 deletes the user_skills row inserted by Q38 within the same pass), the benchmark is repeatable without re-seeding.

## 4. Results by Section

Across all 45 queries (3-run averages): **total execution 4.949 ms**, mean 0.110 ms, median 0.042 ms, fastest 0.006 ms (Q45) and 0.006 ms (Q2), slowest 0.857 ms (Q34). 0 of 45 queries averaged 1 ms or more; the nine write queries (Q37-Q45) all averaged 0.105 ms or less.


### Section 1: Basic SELECT Queries

*#### Read path baseline — every table fits in a handful of buffer pages, so Seq Scans win everywhere.*

| Q | Description | Plan (top node) | Planning (ms) | Run 1 (ms) | Run 2 (ms) | Run 3 (ms) | Average (ms) | Rows |
|---|---|---|---|---|---|---|---|---|
| Q1 | Display all registered users. | Seq Scan on users | 0.141 | 0.021 | 0.021 | 0.022 | 0.021 | 200 |
| Q2 | Display user details using user ID. | Index Scan using users_pkey on users | 0.022 | 0.006 | 0.006 | 0.006 | 0.006 | 1 |
| Q3 | Display all available skills. | Sort | 0.083 | 0.073 | 0.074 | 0.072 | 0.073 | 60 |
| Q4 | Display all teaching skills. | Seq Scan on user_skills | 0.103 | 0.041 | 0.042 | 0.043 | 0.042 | 407 |
| Q5 | Display all learning skills. | Seq Scan on user_skills | 0.009 | 0.035 | 0.037 | 0.036 | 0.036 | 408 |
| Q6 | Display all active matches. | Seq Scan on matches | 0.126 | 0.018 | 0.019 | 0.019 | 0.019 | 222 |
| Q7 | Display all pending exchange requests. | Seq Scan on exchange_requests | 0.133 | 0.017 | 0.019 | 0.019 | 0.018 | 96 |
| Q8 | Display all unread notifications. | Seq Scan on notifications | 0.086 | 0.061 | 0.060 | 0.062 | 0.061 | 588 |

Section total (sum of averages): **0.276 ms** for 8 queries — full plan structures in [`plans/01_basic_select_queries.md`](plans/01_basic_select_queries.md).

All eight queries are trivial full-table reads; the only index usage is the primary-key lookup in Q2. This is the expected baseline: with tables of 60-1,002 rows (2-15 pages), a Seq Scan reads everything directly from the buffer cache and no secondary index can beat it. Everything averages 0.006-0.061 ms, well below any human-perceivable latency. These queries matter at scale rather than at this size — for example, Q8's global unread sweep would degrade linearly as notifications grow, which is why the production notification inbox filters by user_id and uses idx_notifications_user_read_created.


### Section 2: WHERE, ORDER BY and DISTINCT

*#### Filters and sorts are cheap; the planner still prefers scans because selectivity is low at this scale.*

| Q | Description | Plan (top node) | Planning (ms) | Run 1 (ms) | Run 2 (ms) | Run 3 (ms) | Average (ms) | Rows |
|---|---|---|---|---|---|---|---|---|
| Q9 | Find users from a particular location. | Seq Scan on users | 0.007 | 0.014 | 0.013 | 0.014 | 0.014 | 40 |
| Q10 | Display users in descending order of rating. | Sort | 0.012 | 0.045 | 0.039 | 0.039 | 0.041 | 200 |
| Q11 | Display all distinct skill names. | Unique | 0.010 | 0.069 | 0.065 | 0.080 | 0.071 | 60 |
| Q12 | Find users with a rating greater than 4. | Sort | 0.011 | 0.016 | 0.015 | 0.015 | 0.015 | 26 |

Section total (sum of averages): **0.141 ms** for 4 queries — full plan structures in [`plans/02_where_order_by_distinct.md`](plans/02_where_order_by_distinct.md).

The planner applies the same logic to filtered reads: even a selective predicate like location = 'Delhi' (40 of 200 rows) is resolved by scanning 6 pages rather than an index plus heap probes. Two details are worth noting. First, Q10 uses ORDER BY rating DESC NULLS LAST — the explicit NULLS LAST is what keeps unrated users below rated ones, because PostgreSQL sorts NULLs as largest by default. Second, Q11's DISTINCT is logically redundant: skill_name carries a UNIQUE constraint, and the plan shows all 60 rows passing through the Unique node unchanged — the query still pays for a sort it does not need.


### Section 3: JOIN Queries

*#### The most expensive section — multi-way Hash Joins plus large ORDER BY sorts.*

| Q | Description | Plan (top node) | Planning (ms) | Run 1 (ms) | Run 2 (ms) | Run 3 (ms) | Average (ms) | Rows |
|---|---|---|---|---|---|---|---|---|
| Q13 | Display users along with their teaching and learning skills. | Sort | 0.125 | 0.849 | 0.804 | 0.856 | 0.836 | 815 |
| Q14 | Find users who can teach a particular skill. | Sort | 0.071 | 0.028 | 0.026 | 0.028 | 0.027 | 8 |
| Q15 | Find users who want to learn a particular skill. | Nested Loop | 0.057 | 0.015 | 0.014 | 0.015 | 0.015 | 8 |
| Q16 | Display matches with both users' names. | Hash Join | 0.062 | 0.098 | 0.096 | 0.099 | 0.098 | 300 |
| Q17 | Display exchange requests with sender and skill details. | Hash Join | 0.087 | 0.115 | 0.114 | 0.106 | 0.112 | 297 |
| Q18 | Display conversations with their associated matches. | Hash Join | 0.114 | 0.058 | 0.068 | 0.052 | 0.059 | 233 |
| Q19 | Display messages with sender information. | Sort | 0.135 | 0.749 | 0.735 | 0.811 | 0.765 | 3019 |
| Q20 | Display reviews with reviewer and reviewee names. | Hash Join | 0.139 | 0.101 | 0.101 | 0.101 | 0.101 | 358 |
| Q21 | Display notifications with user information. | Sort | 0.041 | 0.249 | 0.251 | 0.254 | 0.251 | 1002 |

Section total (sum of averages): **2.264 ms** for 9 queries — full plan structures in [`plans/03_join_queries.md`](plans/03_join_queries.md).

This section carries the largest share of the suite's cost. The planner consistently picks **Hash Joins** when a query touches a large fraction of both tables (Q13, Q16-Q21): it builds an in-memory hash table on the smaller side and probes it with the larger one, avoiding repeated index descents. Where a filter is selective, it switches to **nested loops driven by a Bitmap Index Scan** — Q14 and Q15 resolve skill_name = 'React'/'Python' through idx_user_skills_skill_id and touch only the matching heap pages. The section's cost is dominated by full-table joins and final ORDER BY sorts: Q13 joins all 815 user_skills rows to users and skills and sorts them (0.836 ms), Q19 sorts 3,019 joined message rows (0.765 ms), and Q21 sorts 1,002 notification rows (0.251 ms). In the real application both message and notification queries run per-conversation or per-user, and the composite indexes idx_messages_conversation_sent and idx_notifications_user_read_created then provide pre-sorted input, eliminating the sort node entirely.


### Section 4: Aggregate Functions

*#### Aggregates: HashAggregate is cheap, GroupAggregate (sorted) is not; Q24 is the section's high-water mark.*

| Q | Description | Plan (top node) | Planning (ms) | Run 1 (ms) | Run 2 (ms) | Run 3 (ms) | Average (ms) | Rows |
|---|---|---|---|---|---|---|---|---|
| Q22 | Count the total number of registered users. | Aggregate | 0.012 | 0.019 | 0.015 | 0.015 | 0.016 | 1 |
| Q23 | Count the total number of skills. | Aggregate | 0.006 | 0.006 | 0.007 | 0.007 | 0.007 | 1 |
| Q24 | Count the number of users associated with each skill. | Sort | 0.046 | 0.290 | 0.249 | 0.246 | 0.262 | 60 |
| Q25 | Find the average user rating. | Aggregate | 0.019 | 0.026 | 0.020 | 0.020 | 0.022 | 1 |
| Q26 | Find the highest and lowest user ratings. | Aggregate | 0.017 | 0.015 | 0.016 | 0.015 | 0.015 | 1 |
| Q27 | Count the total number of matches by status. | HashAggregate | 0.010 | 0.038 | 0.027 | 0.027 | 0.031 | 3 |
| Q28 | Count exchange requests by status. | HashAggregate | 0.010 | 0.032 | 0.026 | 0.027 | 0.028 | 3 |
| Q29 | Find the most popular teaching skills. | Limit | 0.037 | 0.105 | 0.093 | 0.093 | 0.097 | 10 |
| Q30 | Calculate average review rating for each user. | Sort | 0.043 | 0.144 | 0.153 | 0.144 | 0.147 | 200 |

Section total (sum of averages): **0.625 ms** for 9 queries — full plan structures in [`plans/04_aggregate_functions.md`](plans/04_aggregate_functions.md).

Aggregates are cheap when they collapse many rows into few groups via HashAggregate (Q27-Q29, Q31) and more expensive when the grouping strategy needs sorted input (Q24's GroupAggregate over a Hash Right Join, 0.262 ms). Two structural observations stand out. COUNT(*) (Q22) still scans every row — PostgreSQL maintains no row counter — and at production scale an exact count of messages would need either an index-only scan (after a VACUUM freeze) or an approximation. And Q30 is the concrete cost of the controlled denormalization documented in 01_normalization.md §10: computing AVG(rating) from REVIEWS averages 0.147 ms today and grows with the review table; USERS.rating exists so that profile views never run this query.


### Section 5: GROUP BY and HAVING

*#### HAVING adds only a post-aggregate filter; join shape dominates the cost.*

| Q | Description | Plan (top node) | Planning (ms) | Run 1 (ms) | Run 2 (ms) | Run 3 (ms) | Average (ms) | Rows |
|---|---|---|---|---|---|---|---|---|
| Q31 | Display skills having more than one associated user. | HashAggregate | 0.029 | 0.122 | 0.120 | 0.120 | 0.121 | 60 |
| Q32 | Display users who have received more than one review. | HashAggregate | 0.034 | 0.083 | 0.084 | 0.082 | 0.083 | 106 |

Section total (sum of averages): **0.204 ms** for 2 queries — full plan structures in [`plans/05_group_by_having.md`](plans/05_group_by_having.md).

HAVING is implemented as a Filter placed on top of the aggregate node, so its cost is the full grouping plus a cheap per-group check. Q31 shows the data at this scale saturates the predicate — all 60 skills have more than one interested user, so the filter removes nothing. The interesting planner detail is the join shape: Q31 builds on a Hash Join over user_skills and Q32 on reviews, and neither uses the secondary indexes because grouping must consume every row anyway.


### Section 6: Subqueries

*#### Planner rewrites shine here (InitPlan, Anti Join) — and Q34 shows how an OR defeats them.*

| Q | Description | Plan (top node) | Planning (ms) | Run 1 (ms) | Run 2 (ms) | Run 3 (ms) | Average (ms) | Rows |
|---|---|---|---|---|---|---|---|---|
| Q33 | Find users whose rating is above the average rating. | Seq Scan on users | 0.016 | 0.030 | 0.029 | 0.030 | 0.030 | 70 |
| Q34 | Find users who have at least one active match. | Nested Loop Semi Join | 0.030 | 0.850 | 0.843 | 0.878 | 0.857 | 176 |
| Q35 | Find skills that have at least one teacher. | Hash Join | 0.031 | 0.062 | 0.062 | 0.063 | 0.062 | 60 |
| Q36 | Find users who have not received any reviews. | Hash Anti Join | 0.035 | 0.042 | 0.042 | 0.043 | 0.042 | 39 |

Section total (sum of averages): **0.991 ms** for 4 queries — full plan structures in [`plans/06_subqueries.md`](plans/06_subqueries.md).

Subqueries reveal PostgreSQL's plan rewrites. Q33's scalar subquery became an **InitPlan** — the average is computed once and consulted as a constant, not re-evaluated per row. Q36's NOT EXISTS became a **Hash Anti Join**, and Q35's EXISTS became a hash semi-join, both far cheaper than the naive per-row execution their SQL shape suggests. Q34 is the exception and the lesson of this benchmark: the OR of two correlated probes (user1_id = u.id OR user2_id = u.id) defeats index-assisted semi-joins, forcing a Nested Loop Semi Join with a brute-force Join Filter that rejected 20,897 (user, match) pairs — averaging 0.857 ms, the slowest query in the suite. §7 shows two rewrites that measured several times faster on identical data.


### Section 7: INSERT Queries

*#### INSERT cost is index maintenance: more indexes per table, more time per row.*

| Q | Description | Plan (top node) | Planning (ms) | Run 1 (ms) | Run 2 (ms) | Run 3 (ms) | Average (ms) | Rows |
|---|---|---|---|---|---|---|---|---|
| Q37 | Insert a new skill into the platform. | Insert on skills | 0.004 | 0.167 | 0.049 | 0.055 | 0.090 | 1 |
| Q38 | Add a teaching skill to a user. | Insert on user_skills | 0.003 | 0.107 | 0.098 | 0.109 | 0.105 | 1 |
| Q39 | Add a learning skill to a user. | Insert on user_skills | 0.003 | 0.036 | 0.027 | 0.025 | 0.029 | 1 |

Section total (sum of averages): **0.224 ms** for 3 queries — full plan structures in [`plans/07_insert_queries.md`](plans/07_insert_queries.md).

Single-row INSERTs complete in ~0.029-0.105 ms on average. The spread reflects index and constraint maintenance: Q37 maintains two indexes (PK + UNIQUE skill_name), while Q38/Q39 maintain three (PK, the composite UNIQUE (user_id, skill_id, skill_type) index and idx_user_skills_skill_id) and fire the two foreign-key check triggers visible in their plan output. These statements ran inside the benchmark transaction and were rolled back, so 'JavaScript' and the two user_skills rows never persisted. All three queries succeeded — the seed dataset deliberately reserves 'JavaScript', (user 1, skill 1, 'teach') and (user 1, skill 2, 'learn') for them.


### Section 8: UPDATE Queries

*#### PK-driven updates except Q41, where the planner proves a scan beats an index on a tiny table.*

| Q | Description | Plan (top node) | Planning (ms) | Run 1 (ms) | Run 2 (ms) | Run 3 (ms) | Average (ms) | Rows |
|---|---|---|---|---|---|---|---|---|
| Q40 | Update a user's profile information. | Update on users | 0.011 | 0.078 | 0.078 | 0.067 | 0.074 | 1 |
| Q41 | Update the status of an exchange request. | Update on exchange_requests | 0.010 | 0.060 | 0.048 | 0.045 | 0.051 | 1 |
| Q42 | Mark a notification as read. | Update on notifications | 0.008 | 0.031 | 0.034 | 0.042 | 0.036 | 1 |
| Q43 | Mark a message as read. | Update on messages | 0.008 | 0.044 | 0.052 | 0.050 | 0.049 | 1 |

Section total (sum of averages): **0.210 ms** for 4 queries — full plan structures in [`plans/08_update_queries.md`](plans/08_update_queries.md).

Every UPDATE locates its target through the primary-key index except Q41, where the planner judged a Seq Scan of 297 rows cheaper than a PK probe — the crossover point where full scans beat point lookups sits at roughly a thousand rows on modern hardware. The read-receipt updates (Q42, Q43) are the most frequent write paths in a chat application and average 0.036-0.049 ms each. Because the updated column (is_read) is not itself indexed, no index maintenance follows the heap update.


### Section 9: DELETE Queries

*#### Constraint indexes double as access paths; access-control filters cost nothing measurable.*

| Q | Description | Plan (top node) | Planning (ms) | Run 1 (ms) | Run 2 (ms) | Run 3 (ms) | Average (ms) | Rows |
|---|---|---|---|---|---|---|---|---|
| Q44 | Remove a skill association from a user's profile. | Delete on user_skills | 0.013 | 0.008 | 0.008 | 0.009 | 0.008 | 1 |
| Q45 | Delete a notification belonging to a user. | Delete on notifications | 0.012 | 0.005 | 0.006 | 0.006 | 0.006 | 1 |

Section total (sum of averages): **0.014 ms** for 2 queries — full plan structures in [`plans/09_delete_queries.md`](plans/09_delete_queries.md).

Q44 is the benchmark's nicest demonstration that constraints are indexes in disguise: the delete is resolved through user_skills_no_duplicates, the composite UNIQUE index created by the schema's deduplication rule. Q45 adds a Filter on user_id = 1 — an access-control check enforced in the WHERE clause, not just in application code — at an average cost of 0.006 ms. Both deletes ran inside the rolled-back benchmark transaction.

## 5. The Five Slowest Queries

| Rank | Q | Description | Average (ms) | Why it costs more |
|---|---|---|---|---|
| 1 | Q34 | Users with at least one active match | 0.857 | OR of two correlated probes forces a brute-force Nested Loop Semi Join over all user x match pairs |
| 2 | Q13 | Users with their teaching/learning skills | 0.836 | Largest join volume in the suite: 815 user_skills rows joined twice, then sorted |
| 3 | Q19 | Messages with sender information | 0.765 | Hash Join of 3,019 messages followed by a full ORDER BY sent_at sort |
| 4 | Q24 | User count per skill | 0.262 | LEFT JOIN forces GroupAggregate on sorted input — the dearest aggregate shape |
| 5 | Q21 | Notifications with user information | 0.251 | 1,002-row join plus sort by created_at DESC |

### Deep dive: Q34 (avg 0.857 ms)

```text
Nested Loop Semi Join  (cost=0.00..497.05 rows=179 width=16) (actual time=0.003..0.873 rows=176 loops=1)
  Join Filter: ((m.user1_id = u.id) OR (m.user2_id = u.id))
  Rows Removed by Join Filter: 20897
  Buffers: shared hit=9
  ->  Seq Scan on users u  (cost=0.00..8.00 rows=200 width=16) (actual time=0.001..0.005 rows=200 loops=1)
        Buffers: shared hit=6
  ->  Materialize  (cost=0.00..7.86 rows=222 width=8) (actual time=0.000..0.002 rows=105 loops=200)
        Buffers: shared hit=3
        ->  Seq Scan on matches m  (cost=0.00..6.75 rows=222 width=8) (actual time=0.001..0.012 rows=222 loops=1)
              Filter: (status = 'active'::match_status_enum)
              Rows Removed by Filter: 78
              Buffers: shared hit=3
```

The OR inside `EXISTS (… WHERE (m.user1_id = u.id OR m.user2_id = u.id) …)` cannot be split into two index conditions, so the planner materializes the 222 active matches once and rescans that list for each of the 200 users, re-checking the OR pair by pair — the Join Filter rejected **20,897 (user, match) combinations** before finding the first active match for the 176 qualifying users. Neither `idx_matches_user1_id` nor `idx_matches_user2_id` is used.

### Measured rewrites (same data, same result set)

| Formulation | Plan | Run 1 (ms) | Run 2 (ms) | Run 3 (ms) | Average (ms) | Speed-up |
|---|---|---|---|---|---|---|
| Original — OR inside EXISTS | Nested Loop Semi Join + Join Filter | 0.850 | 0.843 | 0.878 | 0.857 | 1x (baseline) |
| UNION of two single-column EXISTS | HashAggregate over two index-assisted arms | 0.158 | 0.159 | 0.175 | 0.164 | ~5.2x |
| `u.id IN (SELECT user1_id …) OR u.id IN (SELECT user2_id …)` | Seq Scan on users + two hashed subqueries | 0.115 | 0.120 | 0.157 | 0.131 | ~6.5x |

The IN-list formulation reads best for a report and gives the planner two independent, index-friendly probes. At 300 matches the absolute saving is under a millisecond; at 300,000 it is the difference between a multi-second query and a sub-second one.

## 6. How the Planner Used — and Ignored — the Schema's Indexes

`03_schema.sql` declares 12 explicit secondary indexes, one explicit unique pair index (`matches_unique_user_pair`) and 13 constraint-backed indexes (9 primary keys + 4 unique constraints) — 26 in total. This is exactly what the planner did with them:

### Indexes that were used

| Index | Kind | Used by | How |
|---|---|---|---|
| `users_pkey` | PK constraint | Q2, Q40 | Index Scan for a single-row lookup / UPDATE by id |
| `notifications_pkey` | PK constraint | Q42, Q45 | Index Scan for read-receipt update and targeted delete |
| `messages_pkey` | PK constraint | Q43 | Index Scan for the read-receipt update |
| `user_skills_no_duplicates` | UNIQUE (user_id, skill_id, skill_type) | Q44 | Index Scan — the constraint doubles as the delete's access path |
| `idx_user_skills_skill_id` | explicit | Q14, Q15 | Bitmap Index Scan after a selective skill_name filter |
| `skills_skill_name_key` | UNIQUE constraint | — (outcompeted) | 60-row table: Seq Scan beat the index probe |

### Indexes that were not used, and why

| Index | Expected consumer | Why it stayed idle here | When it earns its keep |
|---|---|---|---|
| `idx_matches_user1_id` / `idx_matches_user2_id` | Q34, Q6 | Q34's OR blocks index conditions; Q6 filters on status only | Per-user match listings (the app's actual access path) |
| `idx_exchange_requests_sender_status` | Q7 | Leading column is sender_id; Q7 filters only status | My-requests pages filtered by sender + status |
| `idx_exchange_requests_match_id` | Q17 | Q17 joins whole tables; hash join beats index probes | Loading requests of one match |
| `idx_exchange_requests_skill_to_learn/teach` | — | No query filters these columns yet | Skill-popularity / recommendation screens |
| `idx_notifications_user_read_created` | Q8, Q21 | Q8 sweeps all users (no user_id equality); Q21 needs every row | The per-user notification inbox — the production access path |
| `idx_conversations_match_id` | Q18 | Full join of 233 x 300 rows is cheaper than 233 probes | Opening one conversation thread |
| `idx_messages_conversation_sent` | Q19 | Q19 sorts all 3,019 messages globally, not per conversation | Per-conversation chat history (the app's real query) |
| `idx_messages_sender_id` | Q19 | Join needs every message row anyway | Sent-message views, moderation |
| `idx_reviews_reviewee_id` | Q30, Q32 | Grouping consumes all 358 reviews; hash join is cheaper | Ratings shown on one profile |

Two general reasons explain every idle index above:

1. **Scale.** PostgreSQL's cost model compares an index probe (~4 random page reads) against a sequential scan of a table that fits in 2-39 cached pages. Below roughly a thousand rows the scan almost always wins — Q41 even shows the planner rejecting a PK-index probe for a 297-row table.
2. **Leading-column rule.** A btree composite index is only usable when the filters bind its leading column(s): `idx_notifications_user_read_created (user_id, is_read, created_at DESC)` cannot serve Q8's userless unread sweep, and `idx_exchange_requests_sender_status (sender_id, status)` cannot serve Q7's status-only filter.

Neither reason is a design flaw — the indexes were built for the application's point-access workload (inbox, chat history, profile ratings), not for reporting queries that aggregate whole tables. The benchmark simply demonstrates the gap between the two.

## 7. Optimization Recommendations

**1. Rewrite Q34's OR-of-two-columns EXISTS (measured ~5.2-6.5x faster).**

```sql
SELECT id, name
FROM USERS u
WHERE u.id IN (SELECT user1_id FROM MATCHES WHERE status = 'active')
   OR u.id IN (SELECT user2_id FROM MATCHES WHERE status = 'active');
```

Measured on the same dataset (3-run average): 0.857 ms → 0.131 ms. The UNION formulation of two EXISTS arms averages 0.164 ms and returns identical rows.

**2. Never sort the global message table in a chat app.** Q19 (avg 0.765 ms) sorts all 3,019 messages by sent_at. The application only ever reads chat history per conversation, where `idx_messages_conversation_sent (conversation_id, sent_at DESC)` supplies pre-sorted rows and the Sort node disappears. If a global feed is genuinely needed, add an index on `(sent_at DESC)`.

**3. Give Q8's unread sweep a partial index if it is a real screen.** `CREATE INDEX idx_notifications_unread ON notifications (created_at DESC) WHERE NOT is_read;` — a few hundred entries instead of the whole table, and it stays tiny as notifications accumulate.

**4. Consider a partial index for pending requests.** Q7 filters `status = 'pending'`; `CREATE INDEX idx_er_pending ON exchange_requests (requested_at) WHERE status = 'pending';` keeps the inbox-of-requests path fast, while `idx_exchange_requests_sender_status` covers the per-sender view.

**5. Keep the USERS.rating cache.** Q30 (avg 0.147 ms today) is the exact computation every profile view would repeat without the denormalized cache documented in 01_normalization.md §10 — and its cost grows linearly with REVIEWS. A trigger or async worker maintaining the cache remains the right trade-off.

**6. Operational hygiene.** The benchmark needed an explicit `ANALYZE` after bulk load to stop the planner scaling stale page statistics (skills briefly estimated 120 rows for a 60-row table). In production, keep autovacuum's analyze enabled and watch `pg_stat_user_indexes` — the index list in §6 is a working checklist for dropping or re-purposing indexes that never serve real traffic.

## 8. Conclusion

The suite is healthy: 4.949 ms of total average execution time across 45 queries, with every OLTP-shaped query (point lookups, per-user filters, single-row writes) completing in well under a millisecond. The costs concentrate exactly where a reporting-shaped workload should: whole-table joins/sorts (Q13, Q19, Q21) and a planner-hostile OR predicate (Q34). The measurements confirm the schema design choices made in `01_normalization.md` and `03_schema.sql`:

- constraint-backed indexes are load-bearing — the composite UNIQUE index served Q44's delete and the PK indexes carried every targeted write;
- the composite `(conversation_id, sent_at)` and `(user_id, is_read, created_at)` indexes match the application's real access patterns even though the benchmark's table-wide reporting queries could not use them;
- the one genuine defect found (Q34) is a query-shape problem, fixed by a rewrite rather than by adding indexes;
- at this dataset size the planner correctly ignores most secondary indexes — their value will appear with production row counts, and the per-index notes in §6 say when.

## 9. Reproducing This Benchmark

```bash
# 1. fresh database with the official schema
createdb skillor
psql -d skillor -f dbms/03_schema.sql

# 2. load the deterministic benchmark dataset (includes ANALYZE)
psql -d skillor -f dbms/plans/seed_data.sql

# 3. capture any query's real plan and timing (repeat 3 times after warmup for Run 1-3)
psql -d skillor -c "EXPLAIN (ANALYZE, BUFFERS) SELECT id, name FROM USERS WHERE id = 1;"

# 4. for DML queries (Q37-Q45), keep the transaction open and roll back
psql -d skillor
BEGIN;
EXPLAIN (ANALYZE, BUFFERS) INSERT INTO SKILLS (skill_name) VALUES ('JavaScript') RETURNING *;
ROLLBACK;
```

Notes: run step 1 on a **fresh** database so identity ids match the seed's assumptions; timings will differ across machines — treat the plans, not the milliseconds, as the portable result.
