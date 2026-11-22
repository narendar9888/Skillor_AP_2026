# Query Execution Plans — Section 5: GROUP BY and HAVING

**File:** `plans/05_group_by_having.md`  
**Project:** Skillor — Skill Exchange Platform  
**Database:** PostgreSQL 16.2  
**Source:** `04_queries.sql` — Section 5 (GROUP BY and HAVING)  
**Companion report:** [`05_query_timings.md`](../05_query_timings.md)

Each query from `04_queries.sql` was executed twice against the seeded dataset.
The first pass warmed the catalog and page caches; the plan and timings reported here come from
the **second pass**, captured with `EXPLAIN (ANALYZE, BUFFERS)`. Every pass ran inside a single
transaction that was **rolled back** afterwards, so the INSERT/UPDATE/DELETE queries (Q37-Q45)
left the seeded dataset untouched, and `ANALYZE` refreshed planner statistics between passes.


**Benchmark snapshot:** 2 queries | execution time 0.231-0.328 ms | total 0.559 ms | dataset: 200 users, 60 skills, 815 user_skills, 300 matches, 297 exchange_requests, 233 conversations, 3,019 messages, 358 reviews, 1,002 notifications.

---

### Q31. Display skills having more than one associated user.

```sql
SELECT
    s.skill_name,
    COUNT(us.user_id) AS total_users
FROM SKILLS s
JOIN USER_SKILLS us
    ON s.id = us.skill_id
GROUP BY s.id, s.skill_name
HAVING COUNT(us.user_id) > 1;
```

**EXPLAIN (ANALYZE, BUFFERS)** — planning 0.062 ms, execution 0.328 ms, 60 row(s) returned/affected:

```text
HashAggregate  (cost=23.87..24.62 rows=20 width=21) (actual time=0.307..0.316 rows=60 loops=1)
  Group Key: s.id
  Filter: (count(us.user_id) > 1)
  Batches: 1  Memory Usage: 24kB
  Buffers: shared hit=8
  ->  Hash Join  (cost=2.35..19.80 rows=815 width=17) (actual time=0.016..0.187 rows=815 loops=1)
        Hash Cond: (us.skill_id = s.id)
        Buffers: shared hit=8
        ->  Seq Scan on user_skills us  (cost=0.00..15.15 rows=815 width=8) (actual time=0.001..0.046 rows=815 loops=1)
              Buffers: shared hit=7
        ->  Hash  (cost=1.60..1.60 rows=60 width=13) (actual time=0.013..0.013 rows=60 loops=1)
              Buckets: 1024  Batches: 1  Memory Usage: 11kB
              Buffers: shared hit=1
              ->  Seq Scan on skills s  (cost=0.00..1.60 rows=60 width=13) (actual time=0.001..0.006 rows=60 loops=1)
                    Buffers: shared hit=1
Planning:
  Buffers: shared hit=6
Planning Time: 0.062 ms
Execution Time: 0.328 ms
```

**Observation:** HAVING COUNT(us.user_id) > 1 is applied as a Filter on the HashAggregate: 60 skills qualify — every seeded skill has at least two interested users at this scale.

### Q32. Display users who have received more than one review.

```sql
SELECT
    u.id,
    u.name,
    COUNT(r.id) AS total_reviews
FROM USERS u
JOIN REVIEWS r
    ON u.id = r.reviewee_id
GROUP BY u.id, u.name
HAVING COUNT(r.id) > 1;
```

**EXPLAIN (ANALYZE, BUFFERS)** — planning 0.081 ms, execution 0.231 ms, 106 row(s) returned/affected:

```text
HashAggregate  (cost=20.83..23.33 rows=67 width=24) (actual time=0.199..0.218 rows=106 loops=1)
  Group Key: u.id
  Filter: (count(r.id) > 1)
  Batches: 1  Memory Usage: 48kB
  Rows Removed by Filter: 55
  Buffers: shared hit=10
  ->  Hash Join  (cost=10.50..19.04 rows=358 width=20) (actual time=0.042..0.130 rows=358 loops=1)
        Hash Cond: (r.reviewee_id = u.id)
        Buffers: shared hit=10
        ->  Seq Scan on reviews r  (cost=0.00..7.58 rows=358 width=8) (actual time=0.001..0.022 rows=358 loops=1)
              Buffers: shared hit=4
        ->  Hash  (cost=8.00..8.00 rows=200 width=16) (actual time=0.038..0.039 rows=200 loops=1)
              Buckets: 1024  Batches: 1  Memory Usage: 18kB
              Buffers: shared hit=6
              ->  Seq Scan on users u  (cost=0.00..8.00 rows=200 width=16) (actual time=0.001..0.018 rows=200 loops=1)
                    Buffers: shared hit=6
Planning:
  Buffers: shared hit=10
Planning Time: 0.081 ms
Execution Time: 0.231 ms
```

**Observation:** Users with more than one review: HashAggregate with a HAVING filter keeps 106 of 200 users. idx_reviews_reviewee_id is unused because grouping needs all review rows anyway.
