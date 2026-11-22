# Query Execution Plans — Section 4: Aggregate Functions

**File:** `plans/04_aggregate_functions.md`  
**Project:** Skillor — Skill Exchange Platform  
**Database:** PostgreSQL 16.2  
**Source:** `04_queries.sql` — Section 4 (Aggregate Functions)  
**Companion report:** [`05_query_timings.md`](../05_query_timings.md)

Each query from `04_queries.sql` was executed twice against the seeded dataset.
The first pass warmed the catalog and page caches; the plan and timings reported here come from
the **second pass**, captured with `EXPLAIN (ANALYZE, BUFFERS)`. Every pass ran inside a single
transaction that was **rolled back** afterwards, so the INSERT/UPDATE/DELETE queries (Q37-Q45)
left the seeded dataset untouched, and `ANALYZE` refreshed planner statistics between passes.


**Benchmark snapshot:** 9 queries | execution time 0.010-0.569 ms | total 1.381 ms | dataset: 200 users, 60 skills, 815 user_skills, 300 matches, 297 exchange_requests, 233 conversations, 3,019 messages, 358 reviews, 1,002 notifications.

---

### Q22. Count the total number of registered users.

```sql
SELECT COUNT(*) AS total_users
FROM USERS;
```

**EXPLAIN (ANALYZE, BUFFERS)** — planning 0.014 ms, execution 0.028 ms, 1 row(s) returned/affected:

```text
Aggregate  (cost=8.50..8.51 rows=1 width=8) (actual time=0.022..0.023 rows=1 loops=1)
  Buffers: shared hit=6
  ->  Seq Scan on users  (cost=0.00..8.00 rows=200 width=0) (actual time=0.001..0.012 rows=200 loops=1)
        Buffers: shared hit=6
Planning Time: 0.014 ms
Execution Time: 0.028 ms
```

**Observation:** COUNT(*) is an Aggregate over a full Seq Scan — PostgreSQL must still visit every row; nothing caches the answer. 0.028 ms at 200 rows.

### Q23. Count the total number of skills.

```sql
SELECT COUNT(*) AS total_skills
FROM SKILLS;
```

**EXPLAIN (ANALYZE, BUFFERS)** — planning 0.010 ms, execution 0.010 ms, 1 row(s) returned/affected:

```text
Aggregate  (cost=1.75..1.76 rows=1 width=8) (actual time=0.007..0.008 rows=1 loops=1)
  Buffers: shared hit=1
  ->  Seq Scan on skills  (cost=0.00..1.60 rows=60 width=0) (actual time=0.002..0.004 rows=60 loops=1)
        Buffers: shared hit=1
Planning Time: 0.010 ms
Execution Time: 0.010 ms
```

**Observation:** COUNT over the 60-row skills table — the cheapest aggregate in the suite (0.010 ms).

### Q24. Count the number of users associated with each skill.

```sql
SELECT
    s.skill_name,
    COUNT(DISTINCT us.user_id) AS total_users
FROM SKILLS s
LEFT JOIN USER_SKILLS us
    ON s.id = us.skill_id
GROUP BY s.id, s.skill_name
ORDER BY total_users DESC;
```

**EXPLAIN (ANALYZE, BUFFERS)** — planning 0.073 ms, execution 0.569 ms, 60 row(s) returned/affected:

```text
Sort  (cost=67.69..67.84 rows=60 width=21) (actual time=0.552..0.555 rows=60 loops=1)
  Sort Key: (count(DISTINCT us.user_id)) DESC
  Sort Method: quicksort  Memory: 28kB
  Buffers: shared hit=8
  ->  GroupAggregate  (cost=59.20..65.92 rows=60 width=21) (actual time=0.418..0.542 rows=60 loops=1)
        Group Key: s.id
        Buffers: shared hit=8
        ->  Sort  (cost=59.20..61.24 rows=815 width=17) (actual time=0.414..0.444 rows=815 loops=1)
              Sort Key: s.id, us.user_id
              Sort Method: quicksort  Memory: 60kB
              Buffers: shared hit=8
              ->  Hash Right Join  (cost=2.35..19.80 rows=815 width=17) (actual time=0.017..0.188 rows=815 loops=1)
                    Hash Cond: (us.skill_id = s.id)
                    Buffers: shared hit=8
                    ->  Seq Scan on user_skills us  (cost=0.00..15.15 rows=815 width=8) (actual time=0.002..0.046 rows=815 loops=1)
                          Buffers: shared hit=7
                    ->  Hash  (cost=1.60..1.60 rows=60 width=13) (actual time=0.013..0.013 rows=60 loops=1)
                          Buckets: 1024  Batches: 1  Memory Usage: 11kB
                          Buffers: shared hit=1
                          ->  Seq Scan on skills s  (cost=0.00..1.60 rows=60 width=13) (actual time=0.002..0.006 rows=60 loops=1)
                                Buffers: shared hit=1
Planning:
  Buffers: shared hit=6
Planning Time: 0.073 ms
Execution Time: 0.569 ms
```

**Observation:** LEFT JOIN + GROUP BY forced a GroupAggregate (which needs sorted input) on top of a Hash Right Join, making it the most expensive aggregate (0.569 ms). The planner flipped the join sides to build its hash on user_skills.

### Q25. Find the average user rating.

```sql
SELECT
    ROUND(AVG(rating)::numeric, 2) AS average_user_rating
FROM USERS
WHERE rating IS NOT NULL;
```

**EXPLAIN (ANALYZE, BUFFERS)** — planning 0.019 ms, execution 0.048 ms, 1 row(s) returned/affected:

```text
Aggregate  (cost=8.35..8.37 rows=1 width=32) (actual time=0.042..0.042 rows=1 loops=1)
  Buffers: shared hit=6
  ->  Seq Scan on users  (cost=0.00..8.00 rows=141 width=8) (actual time=0.002..0.029 rows=141 loops=1)
        Filter: (rating IS NOT NULL)
        Rows Removed by Filter: 59
        Buffers: shared hit=6
Planning Time: 0.019 ms
Execution Time: 0.048 ms
```

**Observation:** AVG(rating) with an IS NOT NULL pre-filter, computed in a single Aggregate pass over the users scan.

### Q26. Find the highest and lowest user ratings.

```sql
SELECT
    MAX(rating) AS highest_rating,
    MIN(rating) AS lowest_rating
FROM USERS;
```

**EXPLAIN (ANALYZE, BUFFERS)** — planning 0.022 ms, execution 0.035 ms, 1 row(s) returned/affected:

```text
Aggregate  (cost=9.00..9.01 rows=1 width=16) (actual time=0.030..0.030 rows=1 loops=1)
  Buffers: shared hit=6
  ->  Seq Scan on users  (cost=0.00..8.00 rows=200 width=8) (actual time=0.001..0.012 rows=200 loops=1)
        Buffers: shared hit=6
Planning Time: 0.022 ms
Execution Time: 0.035 ms
```

**Observation:** MAX and MIN share one Aggregate pass. With a btree index on rating, PostgreSQL could turn these into instant index lookups, but at 200 rows the scan is cheaper.

### Q27. Count the total number of matches by status.

```sql
SELECT
    status,
    COUNT(*) AS total_matches
FROM MATCHES
GROUP BY status;
```

**EXPLAIN (ANALYZE, BUFFERS)** — planning 0.017 ms, execution 0.063 ms, 3 row(s) returned/affected:

```text
HashAggregate  (cost=7.50..7.53 rows=3 width=12) (actual time=0.056..0.057 rows=3 loops=1)
  Group Key: status
  Batches: 1  Memory Usage: 24kB
  Buffers: shared hit=3
  ->  Seq Scan on matches  (cost=0.00..6.00 rows=300 width=4) (actual time=0.002..0.018 rows=300 loops=1)
        Buffers: shared hit=3
Planning Time: 0.017 ms
Execution Time: 0.063 ms
```

**Observation:** GROUP BY status via HashAggregate — three groups emitted. Trivial cost.

### Q28. Count exchange requests by status.

```sql
SELECT
    status,
    COUNT(*) AS total_requests
FROM EXCHANGE_REQUESTS
GROUP BY status;
```

**EXPLAIN (ANALYZE, BUFFERS)** — planning 0.016 ms, execution 0.061 ms, 3 row(s) returned/affected:

```text
HashAggregate  (cost=8.46..8.48 rows=3 width=12) (actual time=0.056..0.057 rows=3 loops=1)
  Group Key: status
  Batches: 1  Memory Usage: 24kB
  Buffers: shared hit=4
  ->  Seq Scan on exchange_requests  (cost=0.00..6.97 rows=297 width=4) (actual time=0.002..0.019 rows=297 loops=1)
        Buffers: shared hit=4
Planning Time: 0.016 ms
Execution Time: 0.061 ms
```

**Observation:** Same HashAggregate shape as Q27 over exchange_requests (3 status groups).

### Q29. Find the most popular teaching skills.

```sql
SELECT
    s.skill_name,
    COUNT(us.user_id) AS total_teachers
FROM SKILLS s
JOIN USER_SKILLS us
    ON s.id = us.skill_id
WHERE us.skill_type = 'teach'
GROUP BY s.id, s.skill_name
ORDER BY total_teachers DESC
LIMIT 10;
```

**EXPLAIN (ANALYZE, BUFFERS)** — planning 0.081 ms, execution 0.229 ms, 10 row(s) returned/affected:

```text
Limit  (cost=24.62..24.64 rows=10 width=21) (actual time=0.216..0.218 rows=10 loops=1)
  Buffers: shared hit=8
  ->  Sort  (cost=24.62..24.77 rows=60 width=21) (actual time=0.215..0.216 rows=10 loops=1)
        Sort Key: (count(us.user_id)) DESC
        Sort Method: top-N heapsort  Memory: 26kB
        Buffers: shared hit=8
        ->  HashAggregate  (cost=22.72..23.32 rows=60 width=21) (actual time=0.189..0.196 rows=60 loops=1)
              Group Key: s.id
              Batches: 1  Memory Usage: 24kB
              Buffers: shared hit=8
              ->  Hash Join  (cost=2.35..20.68 rows=407 width=17) (actual time=0.017..0.130 rows=407 loops=1)
                    Hash Cond: (us.skill_id = s.id)
                    Buffers: shared hit=8
                    ->  Seq Scan on user_skills us  (cost=0.00..17.19 rows=407 width=8) (actual time=0.002..0.058 rows=407 loops=1)
                          Filter: (skill_type = 'teach'::skill_type_enum)
                          Rows Removed by Filter: 408
                          Buffers: shared hit=7
                    ->  Hash  (cost=1.60..1.60 rows=60 width=13) (actual time=0.013..0.013 rows=60 loops=1)
                          Buckets: 1024  Batches: 1  Memory Usage: 11kB
                          Buffers: shared hit=1
                          ->  Seq Scan on skills s  (cost=0.00..1.60 rows=60 width=13) (actual time=0.001..0.005 rows=60 loops=1)
                                Buffers: shared hit=1
Planning:
  Buffers: shared hit=6
Planning Time: 0.081 ms
Execution Time: 0.229 ms
```

**Observation:** Top-10 teaching skills: filter → HashAggregate → bounded top-N Sort (LIMIT 10 turns the sort into a heap-based top-N). 0.229 ms.

### Q30. Calculate average review rating for each user.

```sql
SELECT
    u.id,
    u.name,
    ROUND(AVG(r.rating)::numeric, 2) AS average_rating,
    COUNT(r.id) AS total_reviews
FROM USERS u
LEFT JOIN REVIEWS r
    ON u.id = r.reviewee_id
GROUP BY u.id, u.name
ORDER BY average_rating DESC NULLS LAST;
```

**EXPLAIN (ANALYZE, BUFFERS)** — planning 0.090 ms, execution 0.338 ms, 200 row(s) returned/affected:

```text
Sort  (cost=32.37..32.87 rows=200 width=56) (actual time=0.312..0.320 rows=200 loops=1)
  Sort Key: (round(avg(r.rating), 2)) DESC NULLS LAST
  Sort Method: quicksort  Memory: 35kB
  Buffers: shared hit=10
  ->  HashAggregate  (cost=21.73..24.73 rows=200 width=56) (actual time=0.215..0.270 rows=200 loops=1)
        Group Key: u.id
        Batches: 1  Memory Usage: 96kB
        Buffers: shared hit=10
        ->  Hash Right Join  (cost=10.50..19.04 rows=358 width=24) (actual time=0.042..0.133 rows=397 loops=1)
              Hash Cond: (r.reviewee_id = u.id)
              Buffers: shared hit=10
              ->  Seq Scan on reviews r  (cost=0.00..7.58 rows=358 width=12) (actual time=0.001..0.020 rows=358 loops=1)
                    Buffers: shared hit=4
              ->  Hash  (cost=8.00..8.00 rows=200 width=16) (actual time=0.038..0.039 rows=200 loops=1)
                    Buckets: 1024  Batches: 1  Memory Usage: 18kB
                    Buffers: shared hit=6
                    ->  Seq Scan on users u  (cost=0.00..8.00 rows=200 width=16) (actual time=0.001..0.018 rows=200 loops=1)
                          Buffers: shared hit=6
Planning:
  Buffers: shared hit=10
Planning Time: 0.090 ms
Execution Time: 0.338 ms
```

**Observation:** Average review rating per user: Hash Right Join + HashAggregate over 358 reviews, then a sort of 200 users (0.338 ms). This is precisely the computation the denormalized USERS.rating cache (01_normalization.md §10) avoids on every profile view.
