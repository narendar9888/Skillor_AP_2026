# Query Execution Plans — Section 1: Basic SELECT Queries

**File:** `plans/01_basic_select_queries.md`  
**Project:** Skillor — Skill Exchange Platform  
**Database:** PostgreSQL 16.2  
**Source:** `04_queries.sql` — Section 1 (Basic SELECT Queries)  
**Companion report:** [`05_query_timings.md`](../05_query_timings.md)

Each query from `04_queries.sql` was executed twice against the seeded dataset.
The first pass warmed the catalog and page caches; the plan and timings reported here come from
the **second pass**, captured with `EXPLAIN (ANALYZE, BUFFERS)`. Every pass ran inside a single
transaction that was **rolled back** afterwards, so the INSERT/UPDATE/DELETE queries (Q37-Q45)
left the seeded dataset untouched, and `ANALYZE` refreshed planner statistics between passes.


**Benchmark snapshot:** 8 queries | execution time 0.009-0.107 ms | total 0.369 ms | dataset: 200 users, 60 skills, 815 user_skills, 300 matches, 297 exchange_requests, 233 conversations, 3,019 messages, 358 reviews, 1,002 notifications.

---

### Q1. Display all registered users.

```sql
SELECT *
FROM USERS;
```

**EXPLAIN (ANALYZE, BUFFERS)** — planning 0.051 ms, execution 0.027 ms, 200 row(s) returned/affected:

```text
Seq Scan on users  (cost=0.00..8.00 rows=200 width=193) (actual time=0.003..0.016 rows=200 loops=1)
  Buffers: shared hit=6
Planning:
  Buffers: shared hit=40
Planning Time: 0.051 ms
Execution Time: 0.027 ms
```

**Observation:** Full Seq Scan over the 200-row users table (6 shared-buffer pages). Reading every row is the cheapest plan at this scale — no index can beat it here.

### Q2. Display user details using user ID.

```sql
SELECT
    id,
    name,
    email,
    bio,
    location,
    profile_pic_url,
    rating
FROM USERS
WHERE id = 1;
```

**EXPLAIN (ANALYZE, BUFFERS)** — planning 0.021 ms, execution 0.009 ms, 1 row(s) returned/affected:

```text
Index Scan using users_pkey on users  (cost=0.14..8.16 rows=1 width=141) (actual time=0.004..0.005 rows=1 loops=1)
  Index Cond: (id = 1)
  Buffers: shared hit=4
Planning Time: 0.021 ms
Execution Time: 0.009 ms
```

**Observation:** Index Scan on users_pkey: a single-row primary-key lookup, the fastest read in the suite (0.009 ms). Point lookups by id always use the PK index.

### Q3. Display all available skills.

```sql
SELECT *
FROM SKILLS
ORDER BY skill_name ASC;
```

**EXPLAIN (ANALYZE, BUFFERS)** — planning 0.039 ms, execution 0.023 ms, 60 row(s) returned/affected:

```text
Sort  (cost=3.37..3.52 rows=60 width=105) (actual time=0.016..0.018 rows=60 loops=1)
  Sort Key: skill_name
  Sort Method: quicksort  Memory: 32kB
  Buffers: shared hit=1
  ->  Seq Scan on skills  (cost=0.00..1.60 rows=60 width=105) (actual time=0.002..0.005 rows=60 loops=1)
        Buffers: shared hit=1
Planning:
  Buffers: shared hit=20
Planning Time: 0.039 ms
Execution Time: 0.023 ms
```

**Observation:** Seq Scan on skills followed by an in-memory quicksort (32 kB) for ORDER BY skill_name. The table is only 2 pages, so sorting 60 rows is nearly free.

### Q4. Display all teaching skills.

```sql
SELECT
    id,
    user_id,
    skill_id,
    skill_type,
    proficiency,
    experience_years
FROM USER_SKILLS
WHERE skill_type = 'teach';
```

**EXPLAIN (ANALYZE, BUFFERS)** — planning 0.027 ms, execution 0.073 ms, 407 row(s) returned/affected:

```text
Seq Scan on user_skills  (cost=0.00..17.19 rows=407 width=30) (actual time=0.003..0.059 rows=407 loops=1)
  Filter: (skill_type = 'teach'::skill_type_enum)
  Rows Removed by Filter: 408
  Buffers: shared hit=7
Planning:
  Buffers: shared hit=24
Planning Time: 0.027 ms
Execution Time: 0.073 ms
```

**Observation:** Seq Scan with a Filter on skill_type = 'teach'. No index is keyed on skill_type alone (idx_user_skills_skill_id leads with skill_id), and at 815 rows a full scan is still the cheapest option.

### Q5. Display all learning skills.

```sql
SELECT
    id,
    user_id,
    skill_id,
    skill_type,
    proficiency,
    experience_years
FROM USER_SKILLS
WHERE skill_type = 'learn';
```

**EXPLAIN (ANALYZE, BUFFERS)** — planning 0.010 ms, execution 0.068 ms, 408 row(s) returned/affected:

```text
Seq Scan on user_skills  (cost=0.00..17.19 rows=408 width=30) (actual time=0.002..0.054 rows=408 loops=1)
  Filter: (skill_type = 'learn'::skill_type_enum)
  Rows Removed by Filter: 407
  Buffers: shared hit=7
Planning Time: 0.010 ms
Execution Time: 0.068 ms
```

**Observation:** Identical plan shape to Q4 for the 'learn' role — the planner re-scans user_skills and filters 408 matching rows.

### Q6. Display all active matches.

```sql
SELECT *
FROM MATCHES
WHERE status = 'active';
```

**EXPLAIN (ANALYZE, BUFFERS)** — planning 0.024 ms, execution 0.032 ms, 222 row(s) returned/affected:

```text
Seq Scan on matches  (cost=0.00..6.75 rows=222 width=24) (actual time=0.003..0.024 rows=222 loops=1)
  Filter: (status = 'active'::match_status_enum)
  Rows Removed by Filter: 78
  Buffers: shared hit=3
Planning:
  Buffers: shared hit=20
Planning Time: 0.024 ms
Execution Time: 0.032 ms
```

**Observation:** Seq Scan + Filter status = 'active' over 300 matches, returning 222. A partial index on (status) WHERE status = 'active' would start to pay off once matches grow into the tens of thousands.

### Q7. Display all pending exchange requests.

```sql
SELECT *
FROM EXCHANGE_REQUESTS
WHERE status = 'pending';
```

**EXPLAIN (ANALYZE, BUFFERS)** — planning 0.031 ms, execution 0.030 ms, 96 row(s) returned/affected:

```text
Seq Scan on exchange_requests  (cost=0.00..7.71 rows=96 width=91) (actual time=0.003..0.025 rows=96 loops=1)
  Filter: (status = 'pending'::request_status_enum)
  Rows Removed by Filter: 201
  Buffers: shared hit=4
Planning:
  Buffers: shared hit=32
Planning Time: 0.031 ms
Execution Time: 0.030 ms
```

**Observation:** Seq Scan + Filter status = 'pending' (96 of 297 requests). idx_exchange_requests_sender_status cannot help because its leading column is sender_id and Q7 filters only on status.

### Q8. Display all unread notifications.

```sql
SELECT *
FROM NOTIFICATIONS
WHERE is_read = FALSE;
```

**EXPLAIN (ANALYZE, BUFFERS)** — planning 0.031 ms, execution 0.107 ms, 588 row(s) returned/affected:

```text
Seq Scan on notifications  (cost=0.00..25.02 rows=588 width=82) (actual time=0.003..0.087 rows=588 loops=1)
  Filter: (NOT is_read)
  Rows Removed by Filter: 414
  Buffers: shared hit=15
Planning:
  Buffers: shared hit=28
Planning Time: 0.031 ms
Execution Time: 0.107 ms
```

**Observation:** The heaviest scan in this section (0.107 ms): 588 of 1,002 notifications are unread. idx_notifications_user_read_created leads with user_id, so a global unread sweep cannot use it — the production inbox always filters by user, which is exactly the shape that index serves.
