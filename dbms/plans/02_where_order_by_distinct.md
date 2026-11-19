# Query Execution Plans — Section 2: WHERE, ORDER BY and DISTINCT

**File:** `plans/02_where_order_by_distinct.md`  
**Project:** Skillor — Skill Exchange Platform  
**Database:** PostgreSQL 16.2  
**Source:** `04_queries.sql` — Section 2 (WHERE, ORDER BY and DISTINCT)  
**Companion report:** [`05_query_timings.md`](../05_query_timings.md)

Each query from `04_queries.sql` was executed twice against the seeded dataset.
The first pass warmed the catalog and page caches; the plan and timings reported here come from
the **second pass**, captured with `EXPLAIN (ANALYZE, BUFFERS)`. Every pass ran inside a single
transaction that was **rolled back** afterwards, so the INSERT/UPDATE/DELETE queries (Q37-Q45)
left the seeded dataset untouched, and `ANALYZE` refreshed planner statistics between passes.


**Benchmark snapshot:** 4 queries | execution time 0.022-0.070 ms | total 0.152 ms | dataset: 200 users, 60 skills, 815 user_skills, 300 matches, 297 exchange_requests, 233 conversations, 3,019 messages, 358 reviews, 1,002 notifications.

---

### Q9. Find users from a particular location.

```sql
SELECT
    id,
    name,
    email,
    location
FROM USERS
WHERE location = 'Delhi';
```

**EXPLAIN (ANALYZE, BUFFERS)** — planning 0.009 ms, execution 0.022 ms, 40 row(s) returned/affected:

```text
Seq Scan on users  (cost=0.00..8.50 rows=40 width=42) (actual time=0.002..0.019 rows=40 loops=1)
  Filter: ((location)::text = 'Delhi'::text)
  Rows Removed by Filter: 160
  Buffers: shared hit=6
Planning Time: 0.009 ms
Execution Time: 0.022 ms
```

**Observation:** Equality filter location = 'Delhi' matches 40 of 200 users via Seq Scan. With the whole table fitting in 6 pages, an index on location would not pay off at this scale.

### Q10. Display users in descending order of rating.

```sql
SELECT
    id,
    name,
    rating
FROM USERS
ORDER BY rating DESC NULLS LAST;
```

**EXPLAIN (ANALYZE, BUFFERS)** — planning 0.010 ms, execution 0.070 ms, 200 row(s) returned/affected:

```text
Sort  (cost=15.64..16.14 rows=200 width=24) (actual time=0.054..0.061 rows=200 loops=1)
  Sort Key: rating DESC NULLS LAST
  Sort Method: quicksort  Memory: 34kB
  Buffers: shared hit=6
  ->  Seq Scan on users  (cost=0.00..8.00 rows=200 width=24) (actual time=0.001..0.022 rows=200 loops=1)
        Buffers: shared hit=6
Planning Time: 0.010 ms
Execution Time: 0.070 ms
```

**Observation:** Sort of all 200 users by rating DESC NULLS LAST. NULLS LAST keeps unrated users (rating IS NULL) at the bottom — under a plain DESC sort, NULLs would appear first.

### Q11. Display all distinct skill names.

```sql
SELECT DISTINCT skill_name
FROM SKILLS
ORDER BY skill_name;
```

**EXPLAIN (ANALYZE, BUFFERS)** — planning 0.012 ms, execution 0.034 ms, 60 row(s) returned/affected:

```text
Unique  (cost=3.37..3.67 rows=60 width=9) (actual time=0.016..0.028 rows=60 loops=1)
  Buffers: shared hit=1
  ->  Sort  (cost=3.37..3.52 rows=60 width=9) (actual time=0.015..0.018 rows=60 loops=1)
        Sort Key: skill_name
        Sort Method: quicksort  Memory: 26kB
        Buffers: shared hit=1
        ->  Seq Scan on skills  (cost=0.00..1.60 rows=60 width=9) (actual time=0.002..0.005 rows=60 loops=1)
              Buffers: shared hit=1
Planning Time: 0.012 ms
Execution Time: 0.034 ms
```

**Observation:** DISTINCT is executed as Unique on top of a Sort. Because skill_name is already UNIQUE by constraint, every row is distinct before dedup — the plan confirms all 60 rows survive it.

### Q12. Find users with a rating greater than 4.

```sql
SELECT
    id,
    name,
    rating
FROM USERS
WHERE rating > 4
ORDER BY rating DESC;
```

**EXPLAIN (ANALYZE, BUFFERS)** — planning 0.013 ms, execution 0.026 ms, 26 row(s) returned/affected:

```text
Sort  (cost=9.11..9.18 rows=26 width=24) (actual time=0.022..0.023 rows=26 loops=1)
  Sort Key: rating DESC
  Sort Method: quicksort  Memory: 26kB
  Buffers: shared hit=6
  ->  Seq Scan on users  (cost=0.00..8.50 rows=26 width=24) (actual time=0.002..0.018 rows=26 loops=1)
        Filter: (rating > '4'::double precision)
        Rows Removed by Filter: 174
        Buffers: shared hit=6
Planning Time: 0.013 ms
Execution Time: 0.026 ms
```

**Observation:** Combined filter + sort: 26 users with rating > 4, ordered by rating. Seq scan plus quicksort, 0.027 ms.
