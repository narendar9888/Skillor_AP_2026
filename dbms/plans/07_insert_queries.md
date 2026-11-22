# Query Execution Plans — Section 7: INSERT Queries

**File:** `plans/07_insert_queries.md`  
**Project:** Skillor — Skill Exchange Platform  
**Database:** PostgreSQL 16.2  
**Source:** `04_queries.sql` — Section 7 (INSERT Queries)  
**Companion report:** [`05_query_timings.md`](../05_query_timings.md)

Each query from `04_queries.sql` was executed twice against the seeded dataset.
The first pass warmed the catalog and page caches; the plan and timings reported here come from
the **second pass**, captured with `EXPLAIN (ANALYZE, BUFFERS)`. Every pass ran inside a single
transaction that was **rolled back** afterwards, so the INSERT/UPDATE/DELETE queries (Q37-Q45)
left the seeded dataset untouched, and `ANALYZE` refreshed planner statistics between passes.


**Benchmark snapshot:** 3 queries | execution time 0.049-0.200 ms | total 0.342 ms | dataset: 200 users, 60 skills, 815 user_skills, 300 matches, 297 exchange_requests, 233 conversations, 3,019 messages, 358 reviews, 1,002 notifications.

> **Note:** the queries in this section **modify data**. During the benchmark they ran inside
> a transaction that was rolled back afterwards, so the seeded dataset was left unchanged.

---

### Q37. Insert a new skill into the platform.

```sql
INSERT INTO SKILLS (
    skill_name,
    description,
    category_id,
    icon_url
)
VALUES (
    'JavaScript',
    'Programming language for web development',
    NULL,
    NULL
)
RETURNING *;
```

**EXPLAIN (ANALYZE, BUFFERS)** — planning 0.009 ms, execution 0.200 ms, 1 row(s) returned/affected:

```text
Insert on skills  (cost=0.00..0.01 rows=1 width=1072) (actual time=0.192..0.192 rows=1 loops=1)
  Buffers: shared hit=6 dirtied=2 written=4
  ->  Result  (cost=0.00..0.01 rows=1 width=1072) (actual time=0.004..0.004 rows=1 loops=1)
        Buffers: shared hit=1
Planning Time: 0.009 ms
Execution Time: 0.200 ms
```

**Observation:** Single-row INSERT with RETURNING (0.200 ms), including maintenance of the PK and the UNIQUE skill_name index. Executed inside the benchmark transaction and rolled back afterwards.

### Q38. Add a teaching skill to a user.

```sql
INSERT INTO USER_SKILLS (
    user_id,
    skill_id,
    skill_type,
    proficiency,
    experience_years
)
VALUES (
    1,
    1,
    'teach',
    'intermediate',
    2
)
RETURNING *;
```

**EXPLAIN (ANALYZE, BUFFERS)** — planning 0.007 ms, execution 0.093 ms, 1 row(s) returned/affected:

```text
Insert on user_skills  (cost=0.00..0.01 rows=1 width=52) (actual time=0.024..0.025 rows=1 loops=1)
  Buffers: shared hit=7
  ->  Result  (cost=0.00..0.01 rows=1 width=52) (actual time=0.003..0.003 rows=1 loops=1)
        Buffers: shared hit=1
Planning Time: 0.007 ms
Trigger for constraint user_skills_user_id_fkey: time=0.044 calls=1
Trigger for constraint user_skills_skill_id_fkey: time=0.018 calls=1
Execution Time: 0.093 ms
```

**Observation:** INSERT into user_skills (0.093 ms) — dearer than a plain insert because three indexes are maintained (PK, the (user_id, skill_id, skill_type) unique index, idx_user_skills_skill_id), and the plan shows the two foreign-key check triggers firing.

### Q39. Add a learning skill to a user.

```sql
INSERT INTO USER_SKILLS (
    user_id,
    skill_id,
    skill_type,
    proficiency,
    experience_years
)
VALUES (
    1,
    2,
    'learn',
    'beginner',
    0
)
RETURNING *;
```

**EXPLAIN (ANALYZE, BUFFERS)** — planning 0.005 ms, execution 0.049 ms, 1 row(s) returned/affected:

```text
Insert on user_skills  (cost=0.00..0.01 rows=1 width=52) (actual time=0.012..0.012 rows=1 loops=1)
  Buffers: shared hit=7
  ->  Result  (cost=0.00..0.01 rows=1 width=52) (actual time=0.001..0.001 rows=1 loops=1)
        Buffers: shared hit=1
Planning Time: 0.005 ms
Trigger for constraint user_skills_user_id_fkey: time=0.016 calls=1
Trigger for constraint user_skills_skill_id_fkey: time=0.011 calls=1
Execution Time: 0.049 ms
```

**Observation:** Same shape as Q38 for the 'learn' role (0.049 ms); the only difference is which enum value flows into skill_type.
