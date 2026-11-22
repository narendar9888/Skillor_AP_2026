# Query Execution Plans — Section 6: Subqueries

**File:** `plans/06_subqueries.md`  
**Project:** Skillor — Skill Exchange Platform  
**Database:** PostgreSQL 16.2  
**Source:** `04_queries.sql` — Section 6 (Subqueries)  
**Companion report:** [`05_query_timings.md`](../05_query_timings.md)

Each query from `04_queries.sql` was executed twice against the seeded dataset.
The first pass warmed the catalog and page caches; the plan and timings reported here come from
the **second pass**, captured with `EXPLAIN (ANALYZE, BUFFERS)`. Every pass ran inside a single
transaction that was **rolled back** afterwards, so the INSERT/UPDATE/DELETE queries (Q37-Q45)
left the seeded dataset untouched, and `ANALYZE` refreshed planner statistics between passes.


**Benchmark snapshot:** 4 queries | execution time 0.062-2.717 ms | total 3.017 ms | dataset: 200 users, 60 skills, 815 user_skills, 300 matches, 297 exchange_requests, 233 conversations, 3,019 messages, 358 reviews, 1,002 notifications.

---

### Q33. Find users whose rating is above the average rating.

```sql
SELECT
    id,
    name,
    rating
FROM USERS
WHERE rating > (
    SELECT AVG(rating)
    FROM USERS
    WHERE rating IS NOT NULL
);
```

**EXPLAIN (ANALYZE, BUFFERS)** — planning 0.031 ms, execution 0.062 ms, 70 row(s) returned/affected:

```text
Seq Scan on users  (cost=8.36..16.86 rows=67 width=24) (actual time=0.034..0.052 rows=70 loops=1)
  Filter: (rating > $0)
  Rows Removed by Filter: 130
  Buffers: shared hit=12
  InitPlan 1 (returns $0)
    ->  Aggregate  (cost=8.35..8.36 rows=1 width=8) (actual time=0.030..0.030 rows=1 loops=1)
          Buffers: shared hit=6
          ->  Seq Scan on users users_1  (cost=0.00..8.00 rows=141 width=8) (actual time=0.001..0.019 rows=141 loops=1)
                Filter: (rating IS NOT NULL)
                Rows Removed by Filter: 59
                Buffers: shared hit=6
Planning Time: 0.031 ms
Execution Time: 0.062 ms
```

**Observation:** The scalar subquery became an InitPlan: AVG(rating) is computed once up front, then the outer Seq Scan filters rating > avg. The subquery is not re-evaluated per row.

### Q34. Find users who have at least one active match.

```sql
SELECT
    id,
    name
FROM USERS u
WHERE EXISTS (
    SELECT 1
    FROM MATCHES m
    WHERE (m.user1_id = u.id OR m.user2_id = u.id)
      AND m.status = 'active'
);
```

**EXPLAIN (ANALYZE, BUFFERS)** — planning 0.057 ms, execution 2.717 ms, 176 row(s) returned/affected:

```text
Nested Loop Semi Join  (cost=0.00..497.05 rows=179 width=16) (actual time=0.006..2.695 rows=176 loops=1)
  Join Filter: ((m.user1_id = u.id) OR (m.user2_id = u.id))
  Rows Removed by Join Filter: 20897
  Buffers: shared hit=9
  ->  Seq Scan on users u  (cost=0.00..8.00 rows=200 width=16) (actual time=0.001..0.014 rows=200 loops=1)
        Buffers: shared hit=6
  ->  Materialize  (cost=0.00..7.86 rows=222 width=8) (actual time=0.000..0.004 rows=105 loops=200)
        Buffers: shared hit=3
        ->  Seq Scan on matches m  (cost=0.00..6.75 rows=222 width=8) (actual time=0.003..0.028 rows=222 loops=1)
              Filter: (status = 'active'::match_status_enum)
              Rows Removed by Filter: 78
              Buffers: shared hit=3
Planning Time: 0.057 ms
Execution Time: 2.717 ms
```

**Observation:** The slowest query in the suite (2.717 ms). The OR inside EXISTS forces a Nested Loop Semi Join whose Join Filter re-checks both user1_id and user2_id against a Materialized Seq Scan of active matches — the filter rejected 20,897 (user, match) pairs before resolving all 200 users. Neither idx_matches_user1_id nor idx_matches_user2_id can serve an OR of two separate probes. See §7 of 05_query_timings.md for rewrites that measured an order of magnitude faster.

### Q35. Find skills that have at least one teacher.

```sql
SELECT
    id,
    skill_name
FROM SKILLS s
WHERE EXISTS (
    SELECT 1
    FROM USER_SKILLS us
    WHERE us.skill_id = s.id
      AND us.skill_type = 'teach'
);
```

**EXPLAIN (ANALYZE, BUFFERS)** — planning 0.070 ms, execution 0.146 ms, 60 row(s) returned/affected:

```text
Hash Join  (cost=19.55..21.98 rows=60 width=13) (actual time=0.122..0.135 rows=60 loops=1)
  Hash Cond: (s.id = us.skill_id)
  Buffers: shared hit=8
  ->  Seq Scan on skills s  (cost=0.00..1.60 rows=60 width=13) (actual time=0.001..0.004 rows=60 loops=1)
        Buffers: shared hit=1
  ->  Hash  (cost=18.80..18.80 rows=60 width=4) (actual time=0.119..0.119 rows=60 loops=1)
        Buckets: 1024  Batches: 1  Memory Usage: 11kB
        Buffers: shared hit=7
        ->  HashAggregate  (cost=18.20..18.80 rows=60 width=4) (actual time=0.109..0.114 rows=60 loops=1)
              Group Key: us.skill_id
              Batches: 1  Memory Usage: 24kB
              Buffers: shared hit=7
              ->  Seq Scan on user_skills us  (cost=0.00..17.19 rows=407 width=4) (actual time=0.002..0.061 rows=407 loops=1)
                    Filter: (skill_type = 'teach'::skill_type_enum)
                    Rows Removed by Filter: 408
                    Buffers: shared hit=7
Planning:
  Buffers: shared hit=4
Planning Time: 0.070 ms
Execution Time: 0.146 ms
```

**Observation:** EXISTS was satisfied with a Hash Semi-style plan: distinct teacher skill_ids are HashAggregated from user_skills, then joined to skills. All 60 skills have at least one teacher.

### Q36. Find users who have not received any reviews.

```sql
SELECT
    id,
    name
FROM USERS u
WHERE NOT EXISTS (
    SELECT 1
    FROM REVIEWS r
    WHERE r.reviewee_id = u.id
);
```

**EXPLAIN (ANALYZE, BUFFERS)** — planning 0.067 ms, execution 0.092 ms, 39 row(s) returned/affected:

```text
Hash Anti Join  (cost=12.05..21.75 rows=39 width=16) (actual time=0.054..0.086 rows=39 loops=1)
  Hash Cond: (u.id = r.reviewee_id)
  Buffers: shared hit=10
  ->  Seq Scan on users u  (cost=0.00..8.00 rows=200 width=16) (actual time=0.001..0.012 rows=200 loops=1)
        Buffers: shared hit=6
  ->  Hash  (cost=7.58..7.58 rows=358 width=4) (actual time=0.052..0.052 rows=358 loops=1)
        Buckets: 1024  Batches: 1  Memory Usage: 21kB
        Buffers: shared hit=4
        ->  Seq Scan on reviews r  (cost=0.00..7.58 rows=358 width=4) (actual time=0.001..0.026 rows=358 loops=1)
              Buffers: shared hit=4
Planning:
  Buffers: shared hit=8
Planning Time: 0.067 ms
Execution Time: 0.092 ms
```

**Observation:** NOT EXISTS was rewritten by the planner into a Hash Anti Join: build a hash of all reviewee_ids, then emit users absent from it — 39 users have never been reviewed.
