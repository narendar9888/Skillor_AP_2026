# Query Execution Plans — Section 9: DELETE Queries

**File:** `plans/09_delete_queries.md`  
**Project:** Skillor — Skill Exchange Platform  
**Database:** PostgreSQL 16.2  
**Source:** `04_queries.sql` — Section 9 (DELETE Queries)  
**Companion report:** [`05_query_timings.md`](../05_query_timings.md)

Each query from `04_queries.sql` was executed twice against the seeded dataset.
The first pass warmed the catalog and page caches; the plan and timings reported here come from
the **second pass**, captured with `EXPLAIN (ANALYZE, BUFFERS)`. Every pass ran inside a single
transaction that was **rolled back** afterwards, so the INSERT/UPDATE/DELETE queries (Q37-Q45)
left the seeded dataset untouched, and `ANALYZE` refreshed planner statistics between passes.


**Benchmark snapshot:** 2 queries | execution time 0.008-0.012 ms | total 0.020 ms | dataset: 200 users, 60 skills, 815 user_skills, 300 matches, 297 exchange_requests, 233 conversations, 3,019 messages, 358 reviews, 1,002 notifications.

> **Note:** the queries in this section **modify data**. During the benchmark they ran inside
> a transaction that was rolled back afterwards, so the seeded dataset was left unchanged.

---

### Q44. Remove a skill association from a user's profile.

```sql
DELETE FROM USER_SKILLS
WHERE user_id = 1
  AND skill_id = 1
  AND skill_type = 'teach'
RETURNING *;
```

**EXPLAIN (ANALYZE, BUFFERS)** — planning 0.039 ms, execution 0.012 ms, 1 row(s) returned/affected:

```text
Delete on user_skills  (cost=0.28..8.30 rows=1 width=6) (actual time=0.006..0.007 rows=1 loops=1)
  Buffers: shared hit=5
  ->  Index Scan using user_skills_no_duplicates on user_skills  (cost=0.28..8.30 rows=1 width=6) (actual time=0.003..0.003 rows=1 loops=1)
        Index Cond: ((user_id = 1) AND (skill_id = 1) AND (skill_type = 'teach'::skill_type_enum))
        Buffers: shared hit=3
Planning Time: 0.039 ms
Execution Time: 0.012 ms
```

**Observation:** DELETE located through an Index Scan on user_skills_no_duplicates — the UNIQUE (user_id, skill_id, skill_type) constraint doubles as the perfect access path for this targeted delete.

### Q45. Delete a notification belonging to a user.

```sql
DELETE FROM NOTIFICATIONS
WHERE id = 1
  AND user_id = 1
RETURNING *;


-- END OF CP3: SKILLOR SQL QUERIES
```

**EXPLAIN (ANALYZE, BUFFERS)** — planning 0.014 ms, execution 0.008 ms, 1 row(s) returned/affected:

```text
Delete on notifications  (cost=0.28..8.29 rows=1 width=6) (actual time=0.004..0.004 rows=1 loops=1)
  Buffers: shared hit=6
  ->  Index Scan using notifications_pkey on notifications  (cost=0.28..8.29 rows=1 width=6) (actual time=0.003..0.003 rows=1 loops=1)
        Index Cond: (id = 1)
        Filter: (user_id = 1)
        Buffers: shared hit=4
Planning Time: 0.014 ms
Execution Time: 0.008 ms
```

**Observation:** DELETE by PK plus a Filter on user_id = 1 (a security check that the row belongs to the caller). 0.008 ms — the fastest write in the suite.
