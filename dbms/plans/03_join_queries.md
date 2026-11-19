# Query Execution Plans — Section 3: JOIN Queries

**File:** `plans/03_join_queries.md`  
**Project:** Skillor — Skill Exchange Platform  
**Database:** PostgreSQL 16.2  
**Source:** `04_queries.sql` — Section 3 (JOIN Queries)  
**Companion report:** [`05_query_timings.md`](../05_query_timings.md)

Each query from `04_queries.sql` was executed twice against the seeded dataset.
The first pass warmed the catalog and page caches; the plan and timings reported here come from
the **second pass**, captured with `EXPLAIN (ANALYZE, BUFFERS)`. Every pass ran inside a single
transaction that was **rolled back** afterwards, so the INSERT/UPDATE/DELETE queries (Q37-Q45)
left the seeded dataset untouched, and `ANALYZE` refreshed planner statistics between passes.


**Benchmark snapshot:** 9 queries | execution time 0.036-1.482 ms | total 3.758 ms | dataset: 200 users, 60 skills, 815 user_skills, 300 matches, 297 exchange_requests, 233 conversations, 3,019 messages, 358 reviews, 1,002 notifications.

---

### Q13. Display users along with their teaching and learning skills.

```sql
-- learning skills.

SELECT
    u.id AS user_id,
    u.name AS user_name,
    s.skill_name,
    us.skill_type,
    us.proficiency,
    us.experience_years
FROM USERS u
JOIN USER_SKILLS us
    ON u.id = us.user_id
JOIN SKILLS s
    ON us.skill_id = s.id
ORDER BY u.name;
```

**EXPLAIN (ANALYZE, BUFFERS)** — planning 0.131 ms, execution 0.722 ms, 815 row(s) returned/affected:

```text
Sort  (cost=71.89..73.92 rows=815 width=43) (actual time=0.657..0.688 rows=815 loops=1)
  Sort Key: u.name
  Sort Method: quicksort  Memory: 83kB
  Buffers: shared hit=14
  ->  Hash Join  (cost=12.85..32.48 rows=815 width=43) (actual time=0.066..0.391 rows=815 loops=1)
        Hash Cond: (us.skill_id = s.id)
        Buffers: shared hit=14
        ->  Hash Join  (cost=10.50..27.83 rows=815 width=38) (actual time=0.045..0.247 rows=815 loops=1)
              Hash Cond: (us.user_id = u.id)
              Buffers: shared hit=13
              ->  Seq Scan on user_skills us  (cost=0.00..15.15 rows=815 width=26) (actual time=0.001..0.045 rows=815 loops=1)
                    Buffers: shared hit=7
              ->  Hash  (cost=8.00..8.00 rows=200 width=16) (actual time=0.037..0.037 rows=200 loops=1)
                    Buckets: 1024  Batches: 1  Memory Usage: 18kB
                    Buffers: shared hit=6
                    ->  Seq Scan on users u  (cost=0.00..8.00 rows=200 width=16) (actual time=0.001..0.018 rows=200 loops=1)
                          Buffers: shared hit=6
        ->  Hash  (cost=1.60..1.60 rows=60 width=13) (actual time=0.015..0.015 rows=60 loops=1)
              Buckets: 1024  Batches: 1  Memory Usage: 11kB
              Buffers: shared hit=1
              ->  Seq Scan on skills s  (cost=0.00..1.60 rows=60 width=13) (actual time=0.002..0.006 rows=60 loops=1)
                    Buffers: shared hit=1
Planning:
  Buffers: shared hit=15
Planning Time: 0.131 ms
Execution Time: 0.722 ms
```

**Observation:** The largest join in the suite: all 815 user_skills rows joined to skills and users, then sorted by name. The planner chose Hash Joins (build an in-memory hash table on the smaller side) instead of 815 index probes — the typical choice when a join fetches most of the table.

### Q14. Find users who can teach a particular skill.

```sql
SELECT
    u.id AS user_id,
    u.name,
    u.email,
    u.location,
    u.rating,
    s.skill_name,
    us.proficiency
FROM USERS u
JOIN USER_SKILLS us
    ON u.id = us.user_id
JOIN SKILLS s
    ON us.skill_id = s.id
WHERE s.skill_name = 'React'
  AND us.skill_type = 'teach'
ORDER BY u.rating DESC NULLS LAST;
```

**EXPLAIN (ANALYZE, BUFFERS)** — planning 0.142 ms, execution 0.044 ms, 8 row(s) returned/affected:

```text
Sort  (cost=15.07..15.09 rows=7 width=69) (actual time=0.032..0.033 rows=8 loops=1)
  Sort Key: u.rating DESC NULLS LAST
  Sort Method: quicksort  Memory: 25kB
  Buffers: shared hit=24
  ->  Nested Loop  (cost=4.40..14.98 rows=7 width=69) (actual time=0.016..0.028 rows=8 loops=1)
        Buffers: shared hit=24
        ->  Nested Loop  (cost=4.26..13.29 rows=7 width=23) (actual time=0.012..0.019 rows=8 loops=1)
              Buffers: shared hit=8
              ->  Seq Scan on skills s  (cost=0.00..1.75 rows=1 width=13) (actual time=0.003..0.005 rows=1 loops=1)
                    Filter: ((skill_name)::text = 'React'::text)
                    Rows Removed by Filter: 59
                    Buffers: shared hit=1
              ->  Bitmap Heap Scan on user_skills us  (cost=4.26..11.47 rows=7 width=18) (actual time=0.007..0.010 rows=8 loops=1)
                    Recheck Cond: (skill_id = s.id)
                    Filter: (skill_type = 'teach'::skill_type_enum)
                    Rows Removed by Filter: 5
                    Heap Blocks: exact=6
                    Buffers: shared hit=7
                    ->  Bitmap Index Scan on idx_user_skills_skill_id  (cost=0.00..4.26 rows=14 width=0) (actual time=0.003..0.003 rows=13 loops=1)
                          Index Cond: (skill_id = s.id)
                          Buffers: shared hit=1
        ->  Index Scan using users_pkey on users u  (cost=0.14..0.24 rows=1 width=50) (actual time=0.001..0.001 rows=1 loops=8)
              Index Cond: (id = us.user_id)
              Buffers: shared hit=16
Planning:
  Buffers: shared hit=14
Planning Time: 0.142 ms
Execution Time: 0.044 ms
```

**Observation:** Selective skill_name = 'React' lookup: Seq Scan on skills (60 rows) → Bitmap Index Scan on idx_user_skills_skill_id → Bitmap Heap Scan of only the matching user_skills pages → sort by rating. This is the first secondary-index usage in the suite.

### Q15. Find users who want to learn a particular skill.

```sql
SELECT
    u.id AS user_id,
    u.name,
    s.skill_name,
    us.proficiency
FROM USERS u
JOIN USER_SKILLS us
    ON u.id = us.user_id
JOIN SKILLS s
    ON us.skill_id = s.id
WHERE s.skill_name = 'Python'
  AND us.skill_type = 'learn';
```

**EXPLAIN (ANALYZE, BUFFERS)** — planning 0.119 ms, execution 0.036 ms, 8 row(s) returned/affected:

```text
Nested Loop  (cost=4.40..14.97 rows=7 width=35) (actual time=0.008..0.027 rows=8 loops=1)
  Buffers: shared hit=23
  ->  Nested Loop  (cost=4.26..13.29 rows=7 width=23) (actual time=0.006..0.021 rows=8 loops=1)
        Buffers: shared hit=7
        ->  Seq Scan on skills s  (cost=0.00..1.75 rows=1 width=13) (actual time=0.002..0.012 rows=1 loops=1)
              Filter: ((skill_name)::text = 'Python'::text)
              Rows Removed by Filter: 59
              Buffers: shared hit=1
        ->  Bitmap Heap Scan on user_skills us  (cost=4.26..11.47 rows=7 width=18) (actual time=0.004..0.007 rows=8 loops=1)
              Recheck Cond: (skill_id = s.id)
              Filter: (skill_type = 'learn'::skill_type_enum)
              Rows Removed by Filter: 3
              Heap Blocks: exact=5
              Buffers: shared hit=6
              ->  Bitmap Index Scan on idx_user_skills_skill_id  (cost=0.00..4.26 rows=14 width=0) (actual time=0.002..0.002 rows=12 loops=1)
                    Index Cond: (skill_id = s.id)
                    Buffers: shared hit=1
  ->  Index Scan using users_pkey on users u  (cost=0.14..0.24 rows=1 width=16) (actual time=0.000..0.001 rows=1 loops=8)
        Index Cond: (id = us.user_id)
        Buffers: shared hit=16
Planning:
  Buffers: shared hit=14
Planning Time: 0.119 ms
Execution Time: 0.036 ms
```

**Observation:** Same access pattern as Q14 for 'Python' learners: nested loop driving a Bitmap Index Scan via idx_user_skills_skill_id, touching only the relevant heap pages.

### Q16. Display matches with both users' names.

```sql
SELECT
    m.id AS match_id,
    u1.name AS user_one,
    u2.name AS user_two,
    m.matched_at,
    m.status
FROM MATCHES m
JOIN USERS u1
    ON m.user1_id = u1.id
JOIN USERS u2
    ON m.user2_id = u2.id;
```

**EXPLAIN (ANALYZE, BUFFERS)** — planning 0.113 ms, execution 0.224 ms, 300 row(s) returned/affected:

```text
Hash Join  (cost=21.00..28.62 rows=300 width=40) (actual time=0.089..0.207 rows=300 loops=1)
  Hash Cond: (m.user2_id = u2.id)
  Buffers: shared hit=15
  ->  Hash Join  (cost=10.50..17.31 rows=300 width=32) (actual time=0.044..0.116 rows=300 loops=1)
        Hash Cond: (m.user1_id = u1.id)
        Buffers: shared hit=9
        ->  Seq Scan on matches m  (cost=0.00..6.00 rows=300 width=24) (actual time=0.001..0.017 rows=300 loops=1)
              Buffers: shared hit=3
        ->  Hash  (cost=8.00..8.00 rows=200 width=16) (actual time=0.041..0.041 rows=200 loops=1)
              Buckets: 1024  Batches: 1  Memory Usage: 18kB
              Buffers: shared hit=6
              ->  Seq Scan on users u1  (cost=0.00..8.00 rows=200 width=16) (actual time=0.001..0.017 rows=200 loops=1)
                    Buffers: shared hit=6
  ->  Hash  (cost=8.00..8.00 rows=200 width=16) (actual time=0.044..0.044 rows=200 loops=1)
        Buckets: 1024  Batches: 1  Memory Usage: 18kB
        Buffers: shared hit=6
        ->  Seq Scan on users u2  (cost=0.00..8.00 rows=200 width=16) (actual time=0.002..0.019 rows=200 loops=1)
              Buffers: shared hit=6
Planning:
  Buffers: shared hit=12
Planning Time: 0.113 ms
Execution Time: 0.224 ms
```

**Observation:** matches is self-joined to users twice (user1_id and user2_id). The planner used two Hash Joins over the small users table rather than 600 separate index probes.

### Q17. Display exchange requests with sender and skill details.

```sql
SELECT
    er.id AS request_id,
    u.name AS sender_name,
    s1.skill_name AS skill_to_learn,
    s2.skill_name AS skill_to_teach,
    er.status,
    er.request_message,
    er.requested_at
FROM EXCHANGE_REQUESTS er
JOIN USERS u
    ON er.sender_id = u.id
JOIN SKILLS s1
    ON er.skill_to_learn_id = s1.id
JOIN SKILLS s2
    ON er.skill_to_teach_id = s2.id;
```

**EXPLAIN (ANALYZE, BUFFERS)** — planning 0.166 ms, execution 0.268 ms, 297 row(s) returned/affected:

```text
Hash Join  (cost=15.20..24.63 rows=297 width=105) (actual time=0.085..0.249 rows=297 loops=1)
  Hash Cond: (er.skill_to_teach_id = s2.id)
  Buffers: shared hit=12
  ->  Hash Join  (cost=12.85..21.45 rows=297 width=100) (actual time=0.071..0.189 rows=297 loops=1)
        Hash Cond: (er.skill_to_learn_id = s1.id)
        Buffers: shared hit=11
        ->  Hash Join  (cost=10.50..18.26 rows=297 width=95) (actual time=0.058..0.129 rows=297 loops=1)
              Hash Cond: (er.sender_id = u.id)
              Buffers: shared hit=10
              ->  Seq Scan on exchange_requests er  (cost=0.00..6.97 rows=297 width=87) (actual time=0.001..0.017 rows=297 loops=1)
                    Buffers: shared hit=4
              ->  Hash  (cost=8.00..8.00 rows=200 width=16) (actual time=0.048..0.048 rows=200 loops=1)
                    Buckets: 1024  Batches: 1  Memory Usage: 18kB
                    Buffers: shared hit=6
                    ->  Seq Scan on users u  (cost=0.00..8.00 rows=200 width=16) (actual time=0.001..0.018 rows=200 loops=1)
                          Buffers: shared hit=6
        ->  Hash  (cost=1.60..1.60 rows=60 width=13) (actual time=0.012..0.012 rows=60 loops=1)
              Buckets: 1024  Batches: 1  Memory Usage: 11kB
              Buffers: shared hit=1
              ->  Seq Scan on skills s1  (cost=0.00..1.60 rows=60 width=13) (actual time=0.001..0.005 rows=60 loops=1)
                    Buffers: shared hit=1
  ->  Hash  (cost=1.60..1.60 rows=60 width=13) (actual time=0.013..0.013 rows=60 loops=1)
        Buckets: 1024  Batches: 1  Memory Usage: 11kB
        Buffers: shared hit=1
        ->  Seq Scan on skills s2  (cost=0.00..1.60 rows=60 width=13) (actual time=0.002..0.006 rows=60 loops=1)
              Buffers: shared hit=1
Planning:
  Buffers: shared hit=20
Planning Time: 0.166 ms
Execution Time: 0.268 ms
```

**Observation:** exchange_requests joined to users plus two skill lookups (learn and teach). Hash Joins again: at 297 requests, hashing four small tables beats 297 x 4 index probes.

### Q18. Display conversations with their associated matches.

```sql
SELECT
    c.id AS conversation_id,
    c.match_id,
    c.created_at,
    c.updated_at,
    m.user1_id,
    m.user2_id,
    m.status AS match_status
FROM CONVERSATIONS c
JOIN MATCHES m
    ON c.match_id = m.id;
```

**EXPLAIN (ANALYZE, BUFFERS)** — planning 0.089 ms, execution 0.122 ms, 233 row(s) returned/affected:

```text
Hash Join  (cost=9.75..14.70 rows=233 width=36) (actual time=0.058..0.110 rows=233 loops=1)
  Hash Cond: (c.match_id = m.id)
  Buffers: shared hit=5
  ->  Seq Scan on conversations c  (cost=0.00..4.33 rows=233 width=24) (actual time=0.002..0.014 rows=233 loops=1)
        Buffers: shared hit=2
  ->  Hash  (cost=6.00..6.00 rows=300 width=16) (actual time=0.053..0.053 rows=300 loops=1)
        Buckets: 1024  Batches: 1  Memory Usage: 23kB
        Buffers: shared hit=3
        ->  Seq Scan on matches m  (cost=0.00..6.00 rows=300 width=16) (actual time=0.002..0.026 rows=300 loops=1)
              Buffers: shared hit=3
Planning:
  Buffers: shared hit=24
Planning Time: 0.089 ms
Execution Time: 0.122 ms
```

**Observation:** conversations ⋈ matches on c.match_id = m.id. Even though idx_conversations_match_id exists, joining the whole tables is cheaper than using it — that index shines only for single-conversation lookups.

### Q19. Display messages with sender information.

```sql
SELECT
    msg.id AS message_id,
    msg.content,
    msg.sent_at,
    msg.is_read,
    u.name AS sender_name
FROM MESSAGES msg
JOIN USERS u
    ON msg.sender_id = u.id
ORDER BY msg.sent_at ASC;
```

**EXPLAIN (ANALYZE, BUFFERS)** — planning 0.079 ms, execution 1.482 ms, 3019 row(s) returned/affected:

```text
Sort  (cost=262.28..269.83 rows=3019 width=67) (actual time=1.270..1.383 rows=3019 loops=1)
  Sort Key: msg.sent_at
  Sort Method: quicksort  Memory: 388kB
  Buffers: shared hit=45
  ->  Hash Join  (cost=10.50..87.78 rows=3019 width=67) (actual time=0.045..0.726 rows=3019 loops=1)
        Hash Cond: (msg.sender_id = u.id)
        Buffers: shared hit=45
        ->  Seq Scan on messages msg  (cost=0.00..69.19 rows=3019 width=59) (actual time=0.001..0.175 rows=3019 loops=1)
              Buffers: shared hit=39
        ->  Hash  (cost=8.00..8.00 rows=200 width=16) (actual time=0.042..0.043 rows=200 loops=1)
              Buckets: 1024  Batches: 1  Memory Usage: 18kB
              Buffers: shared hit=6
              ->  Seq Scan on users u  (cost=0.00..8.00 rows=200 width=16) (actual time=0.001..0.018 rows=200 loops=1)
                    Buffers: shared hit=6
Planning:
  Buffers: shared hit=30
Planning Time: 0.079 ms
Execution Time: 1.482 ms
```

**Observation:** Second-slowest query overall (1.482 ms): a Hash Join of all 3,019 messages with users, then a full sort by sent_at. The application inbox filters by conversation_id first, which idx_messages_conversation_sent (conversation_id, sent_at DESC) serves directly.

### Q20. Display reviews with reviewer and reviewee names.

```sql
SELECT
    r.id AS review_id,
    u1.name AS reviewer_name,
    u2.name AS reviewee_name,
    r.rating,
    r.comment,
    r.created_at
FROM REVIEWS r
JOIN USERS u1
    ON r.reviewer_id = u1.id
JOIN USERS u2
    ON r.reviewee_id = u2.id;
```

**EXPLAIN (ANALYZE, BUFFERS)** — planning 0.160 ms, execution 0.261 ms, 358 row(s) returned/affected:

```text
Hash Join  (cost=21.00..30.50 rows=358 width=89) (actual time=0.100..0.241 rows=358 loops=1)
  Hash Cond: (r.reviewee_id = u2.id)
  Buffers: shared hit=16
  ->  Hash Join  (cost=10.50..19.04 rows=358 width=81) (actual time=0.052..0.137 rows=358 loops=1)
        Hash Cond: (r.reviewer_id = u1.id)
        Buffers: shared hit=10
        ->  Seq Scan on reviews r  (cost=0.00..7.58 rows=358 width=73) (actual time=0.001..0.021 rows=358 loops=1)
              Buffers: shared hit=4
        ->  Hash  (cost=8.00..8.00 rows=200 width=16) (actual time=0.048..0.048 rows=200 loops=1)
              Buckets: 1024  Batches: 1  Memory Usage: 18kB
              Buffers: shared hit=6
              ->  Seq Scan on users u1  (cost=0.00..8.00 rows=200 width=16) (actual time=0.001..0.024 rows=200 loops=1)
                    Buffers: shared hit=6
  ->  Hash  (cost=8.00..8.00 rows=200 width=16) (actual time=0.046..0.046 rows=200 loops=1)
        Buckets: 1024  Batches: 1  Memory Usage: 18kB
        Buffers: shared hit=6
        ->  Seq Scan on users u2  (cost=0.00..8.00 rows=200 width=16) (actual time=0.002..0.021 rows=200 loops=1)
              Buffers: shared hit=6
Planning:
  Buffers: shared hit=40
Planning Time: 0.160 ms
Execution Time: 0.261 ms
```

**Observation:** reviews ⋈ users twice for reviewer and reviewee names. A Hash Join over 358 reviews; idx_reviews_reviewee_id is not used because the query needs every review row anyway.

### Q21. Display notifications with user information.

```sql
SELECT
    n.id AS notification_id,
    u.name AS user_name,
    n.type,
    n.message,
    n.is_read,
    n.created_at
FROM NOTIFICATIONS n
JOIN USERS u
    ON n.user_id = u.id
ORDER BY n.created_at DESC;
```

**EXPLAIN (ANALYZE, BUFFERS)** — planning 0.069 ms, execution 0.599 ms, 1002 row(s) returned/affected:

```text
Sort  (cost=88.15..90.65 rows=1002 width=86) (actual time=0.524..0.562 rows=1002 loops=1)
  Sort Key: n.created_at DESC
  Sort Method: quicksort  Memory: 137kB
  Buffers: shared hit=21
  ->  Hash Join  (cost=10.50..38.21 rows=1002 width=86) (actual time=0.049..0.292 rows=1002 loops=1)
        Hash Cond: (n.user_id = u.id)
        Buffers: shared hit=21
        ->  Seq Scan on notifications n  (cost=0.00..25.02 rows=1002 width=78) (actual time=0.002..0.062 rows=1002 loops=1)
              Buffers: shared hit=15
        ->  Hash  (cost=8.00..8.00 rows=200 width=16) (actual time=0.042..0.042 rows=200 loops=1)
              Buckets: 1024  Batches: 1  Memory Usage: 18kB
              Buffers: shared hit=6
              ->  Seq Scan on users u  (cost=0.00..8.00 rows=200 width=16) (actual time=0.001..0.018 rows=200 loops=1)
                    Buffers: shared hit=6
Planning:
  Buffers: shared hit=10
Planning Time: 0.069 ms
Execution Time: 0.599 ms
```

**Observation:** notifications ⋈ users and a sort of 1,002 rows by created_at DESC (0.599 ms). The production notification list filters by user_id first, letting idx_notifications_user_read_created do the heavy lifting.
