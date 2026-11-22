# Query Execution Plans — Section 8: UPDATE Queries

**File:** `plans/08_update_queries.md`  
**Project:** Skillor — Skill Exchange Platform  
**Database:** PostgreSQL 16.2  
**Source:** `04_queries.sql` — Section 8 (UPDATE Queries)  
**Companion report:** [`05_query_timings.md`](../05_query_timings.md)

Each query from `04_queries.sql` was executed twice against the seeded dataset.
The first pass warmed the catalog and page caches; the plan and timings reported here come from
the **second pass**, captured with `EXPLAIN (ANALYZE, BUFFERS)`. Every pass ran inside a single
transaction that was **rolled back** afterwards, so the INSERT/UPDATE/DELETE queries (Q37-Q45)
left the seeded dataset untouched, and `ANALYZE` refreshed planner statistics between passes.


**Benchmark snapshot:** 4 queries | execution time 0.017-0.037 ms | total 0.109 ms | dataset: 200 users, 60 skills, 815 user_skills, 300 matches, 297 exchange_requests, 233 conversations, 3,019 messages, 358 reviews, 1,002 notifications.

> **Note:** the queries in this section **modify data**. During the benchmark they ran inside
> a transaction that was rolled back afterwards, so the seeded dataset was left unchanged.

---

### Q40. Update a user's profile information.

```sql
UPDATE USERS
SET
    name = 'Updated Name',
    bio = 'Interested in learning and sharing skills.',
    location = 'Delhi',
    updated_at = CURRENT_TIMESTAMP
WHERE id = 1
RETURNING *;
```

**EXPLAIN (ANALYZE, BUFFERS)** — planning 0.013 ms, execution 0.032 ms, 1 row(s) returned/affected:

```text
Update on users  (cost=0.14..8.16 rows=1 width=1078) (actual time=0.024..0.025 rows=1 loops=1)
  Buffers: shared hit=11
  ->  Index Scan using users_pkey on users  (cost=0.14..8.16 rows=1 width=1078) (actual time=0.002..0.002 rows=1 loops=1)
        Index Cond: (id = 1)
        Buffers: shared hit=2
Planning Time: 0.013 ms
Execution Time: 0.032 ms
```

**Observation:** UPDATE by primary key: Index Scan on users_pkey locates the row, and none of the updated columns are indexed, so no index maintenance is needed beyond the heap tuple rewrite.

### Q41. Update the status of an exchange request.

```sql
UPDATE EXCHANGE_REQUESTS
SET status = 'accepted'
WHERE id = 1
RETURNING *;
```

**EXPLAIN (ANALYZE, BUFFERS)** — planning 0.017 ms, execution 0.037 ms, 1 row(s) returned/affected:

```text
Update on exchange_requests  (cost=0.00..7.71 rows=1 width=10) (actual time=0.017..0.033 rows=1 loops=1)
  Buffers: shared hit=15
  ->  Seq Scan on exchange_requests  (cost=0.00..7.71 rows=1 width=10) (actual time=0.002..0.018 rows=1 loops=1)
        Filter: (id = 1)
        Rows Removed by Filter: 296
        Buffers: shared hit=4
Planning Time: 0.017 ms
Execution Time: 0.037 ms
```

**Observation:** UPDATE exchange_requests WHERE id = 1: the planner chose Seq Scan + Filter because at 297 rows a scan is marginally cheaper than the PK probe (cost 7.71 for the scan vs ~8.30 for the probe). At production scale the PK index always wins.

### Q42. Mark a notification as read.

```sql
UPDATE NOTIFICATIONS
SET is_read = TRUE
WHERE id = 1
RETURNING *;
```

**EXPLAIN (ANALYZE, BUFFERS)** — planning 0.011 ms, execution 0.017 ms, 1 row(s) returned/affected:

```text
Update on notifications  (cost=0.28..8.29 rows=1 width=7) (actual time=0.012..0.013 rows=1 loops=1)
  Buffers: shared hit=15
  ->  Index Scan using notifications_pkey on notifications  (cost=0.28..8.29 rows=1 width=7) (actual time=0.003..0.004 rows=1 loops=1)
        Index Cond: (id = 1)
        Buffers: shared hit=5
Planning Time: 0.011 ms
Execution Time: 0.017 ms
```

**Observation:** UPDATE ... SET is_read = TRUE by PK: Index Scan on notifications_pkey plus a heap update (0.017 ms) — the classic read-receipt write path.

### Q43. Mark a message as read.

```sql
UPDATE MESSAGES
SET is_read = TRUE
WHERE id = 1
RETURNING *;
```

**EXPLAIN (ANALYZE, BUFFERS)** — planning 0.012 ms, execution 0.023 ms, 1 row(s) returned/affected:

```text
Update on messages  (cost=0.28..8.30 rows=1 width=7) (actual time=0.018..0.019 rows=1 loops=1)
  Buffers: shared hit=17
  ->  Index Scan using messages_pkey on messages  (cost=0.28..8.30 rows=1 width=7) (actual time=0.003..0.003 rows=1 loops=1)
        Index Cond: (id = 1)
        Buffers: shared hit=5
Planning Time: 0.012 ms
Execution Time: 0.023 ms
```

**Observation:** Same read-receipt pattern as Q42 on messages (0.023 ms), located via messages_pkey.
