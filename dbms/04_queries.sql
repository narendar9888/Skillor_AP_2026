
-- ============================================================
-- SECTION 1: BASIC SELECT QUERIES
-- ============================================================

-- Q1. Display all registered users.
-- READ

SELECT *
FROM USERS;


-- Q2. Display user details using user ID.
-- READ

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


-- Q3. Display all available skills.
-- READ

SELECT *
FROM SKILLS
ORDER BY skill_name ASC;


-- Q4. Display all teaching skills.
-- READ

SELECT
    id,
    user_id,
    skill_id,
    skill_type,
    proficiency,
    experience_years
FROM USER_SKILLS
WHERE skill_type = 'teach';


-- Q5. Display all learning skills.
-- READ

SELECT
    id,
    user_id,
    skill_id,
    skill_type,
    proficiency,
    experience_years
FROM USER_SKILLS
WHERE skill_type = 'learn';


-- Q6. Display all active matches.
-- READ

SELECT *
FROM MATCHES
WHERE status = 'active';


-- Q7. Display all pending exchange requests.
-- READ

SELECT *
FROM EXCHANGE_REQUESTS
WHERE status = 'pending';


-- Q8. Display all unread notifications.
-- READ

SELECT *
FROM NOTIFICATIONS
WHERE is_read = FALSE;


-- ============================================================
-- SECTION 2: WHERE, ORDER BY AND DISTINCT
-- ============================================================

-- Q9. Find users from a particular location.
-- READ

SELECT
    id,
    name,
    email,
    location
FROM USERS
WHERE location = 'Delhi';


-- Q10. Display users in descending order of rating.
-- READ

SELECT
    id,
    name,
    rating
FROM USERS
ORDER BY rating DESC NULLS LAST;


-- Q11. Display all distinct skill names.
-- READ

SELECT DISTINCT skill_name
FROM SKILLS
ORDER BY skill_name;


-- Q12. Find users with a rating greater than 4.
-- READ

SELECT
    id,
    name,
    rating
FROM USERS
WHERE rating > 4
ORDER BY rating DESC;


-- ============================================================
-- SECTION 3: JOIN QUERIES
-- ============================================================

-- Q13. Display users along with their teaching and
-- learning skills.
-- READ

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


-- Q14. Find users who can teach a particular skill.
-- READ

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


-- Q15. Find users who want to learn a particular skill.
-- READ

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


-- Q16. Display matches with both users' names.
-- READ

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


-- Q17. Display exchange requests with sender and skill details.
-- READ

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


-- Q18. Display conversations with their associated matches.
-- READ

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


-- Q19. Display messages with sender information.
-- READ

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


-- Q20. Display reviews with reviewer and reviewee names.
-- READ

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


-- Q21. Display notifications with user information.
-- READ

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


-- ============================================================
-- SECTION 4: AGGREGATE FUNCTIONS
-- ============================================================

-- Q22. Count the total number of registered users.
-- READ

SELECT COUNT(*) AS total_users
FROM USERS;


-- Q23. Count the total number of skills.
-- READ

SELECT COUNT(*) AS total_skills
FROM SKILLS;


-- Q24. Count the number of users associated with each skill.
-- READ

SELECT
    s.skill_name,
    COUNT(DISTINCT us.user_id) AS total_users
FROM SKILLS s
LEFT JOIN USER_SKILLS us
    ON s.id = us.skill_id
GROUP BY s.id, s.skill_name
ORDER BY total_users DESC;


-- Q25. Find the average user rating.
-- READ

SELECT
    ROUND(AVG(rating)::numeric, 2) AS average_user_rating
FROM USERS
WHERE rating IS NOT NULL;


-- Q26. Find the highest and lowest user ratings.
-- READ

SELECT
    MAX(rating) AS highest_rating,
    MIN(rating) AS lowest_rating
FROM USERS;


-- Q27. Count the total number of matches by status.
-- READ

SELECT
    status,
    COUNT(*) AS total_matches
FROM MATCHES
GROUP BY status;


-- Q28. Count exchange requests by status.
-- READ

SELECT
    status,
    COUNT(*) AS total_requests
FROM EXCHANGE_REQUESTS
GROUP BY status;


-- Q29. Find the most popular teaching skills.
-- READ

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


-- Q30. Calculate average review rating for each user.
-- READ

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


-- ============================================================
-- SECTION 5: GROUP BY AND HAVING
-- ============================================================

-- Q31. Display skills having more than one associated user.
-- READ

SELECT
    s.skill_name,
    COUNT(us.user_id) AS total_users
FROM SKILLS s
JOIN USER_SKILLS us
    ON s.id = us.skill_id
GROUP BY s.id, s.skill_name
HAVING COUNT(us.user_id) > 1;


-- Q32. Display users who have received more than one review.
-- READ

SELECT
    u.id,
    u.name,
    COUNT(r.id) AS total_reviews
FROM USERS u
JOIN REVIEWS r
    ON u.id = r.reviewee_id
GROUP BY u.id, u.name
HAVING COUNT(r.id) > 1;


-- ============================================================
-- SECTION 6: SUBQUERIES
-- ============================================================

-- Q33. Find users whose rating is above the average rating.
-- READ

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


-- Q34. Find users who have at least one active match.
-- READ

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


-- Q35. Find skills that have at least one teacher.
-- READ

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


-- Q36. Find users who have not received any reviews.
-- READ

SELECT
    id,
    name
FROM USERS u
WHERE NOT EXISTS (
    SELECT 1
    FROM REVIEWS r
    WHERE r.reviewee_id = u.id
);


-- ============================================================
-- SECTION 7: INSERT QUERIES
-- ============================================================

-- Q37. Insert a new skill into the platform.
-- WRITE

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


-- Q38. Add a teaching skill to a user.
-- WRITE

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


-- Q39. Add a learning skill to a user.
-- WRITE

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


-- ============================================================
-- SECTION 8: UPDATE QUERIES
-- ============================================================

-- Q40. Update a user's profile information.
-- WRITE

UPDATE USERS
SET
    name = 'Updated Name',
    bio = 'Interested in learning and sharing skills.',
    location = 'Delhi',
    updated_at = CURRENT_TIMESTAMP
WHERE id = 1
RETURNING *;


-- Q41. Update the status of an exchange request.
-- WRITE

UPDATE EXCHANGE_REQUESTS
SET status = 'accepted'
WHERE id = 1
RETURNING *;


-- Q42. Mark a notification as read.
-- WRITE

UPDATE NOTIFICATIONS
SET is_read = TRUE
WHERE id = 1
RETURNING *;


-- Q43. Mark a message as read.
-- WRITE

UPDATE MESSAGES
SET is_read = TRUE
WHERE id = 1
RETURNING *;


-- ============================================================
-- SECTION 9: DELETE QUERIES
-- ============================================================

-- Q44. Remove a skill association from a user's profile.
-- WRITE

DELETE FROM USER_SKILLS
WHERE user_id = 1
  AND skill_id = 1
  AND skill_type = 'teach'
RETURNING *;


-- Q45. Delete a notification belonging to a user.
-- WRITE

DELETE FROM NOTIFICATIONS
WHERE id = 1
  AND user_id = 1
RETURNING *;



