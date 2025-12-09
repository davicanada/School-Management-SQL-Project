-- ============================================================================
-- EXAMPLE QUERIES - Sistema de Gestão Escolar
-- ============================================================================
-- Collection of SQL queries demonstrating database capabilities
-- Author: Data Analyst Portfolio
-- ============================================================================

-- ============================================================================
-- 1. BASIC QUERIES
-- ============================================================================

-- Get all active students in an institution
SELECT
  s.id,
  s.name,
  s.registration_number,
  c.name as class_name,
  c.academic_year
FROM students s
LEFT JOIN classes c ON s.class_id = c.id
WHERE s.institution_id = 'institution-uuid-here'
  AND s.deleted_at IS NULL
  AND s.is_active = true
ORDER BY s.name;

-- Count students per class
SELECT
  c.name as class_name,
  c.academic_year,
  COUNT(s.id) as total_students,
  COUNT(CASE WHEN s.is_active THEN 1 END) as active_students
FROM classes c
LEFT JOIN students s ON c.id = s.class_id AND s.deleted_at IS NULL
WHERE c.institution_id = 'institution-uuid-here'
GROUP BY c.id, c.name, c.academic_year
ORDER BY c.academic_year DESC, c.name;

-- ============================================================================
-- 2. JOINS AND AGGREGATIONS
-- ============================================================================

-- Student occurrence report with severity breakdown
SELECT
  s.name as student_name,
  s.registration_number,
  c.name as class_name,
  COUNT(o.id) as total_occurrences,
  COUNT(CASE WHEN ot.severity = 'low' THEN 1 END) as low_severity,
  COUNT(CASE WHEN ot.severity = 'medium' THEN 1 END) as medium_severity,
  COUNT(CASE WHEN ot.severity = 'high' THEN 1 END) as high_severity
FROM students s
LEFT JOIN occurrences o ON s.id = o.student_id
LEFT JOIN occurrence_types ot ON o.occurrence_type_id = ot.id
LEFT JOIN classes c ON s.class_id = c.id
WHERE s.institution_id = 'institution-uuid-here'
  AND s.deleted_at IS NULL
GROUP BY s.id, s.name, s.registration_number, c.name
HAVING COUNT(o.id) > 0
ORDER BY total_occurrences DESC;

-- Teacher activity report
SELECT
  u.name as teacher_name,
  COUNT(DISTINCT o.student_id) as students_with_occurrences,
  COUNT(o.id) as total_occurrences_registered,
  MIN(o.occurred_at) as first_occurrence_date,
  MAX(o.occurred_at) as last_occurrence_date
FROM users u
INNER JOIN occurrences o ON u.id = o.teacher_id
INNER JOIN user_institutions ui ON u.id = ui.user_id
WHERE ui.institution_id = 'institution-uuid-here'
  AND o.occurred_at >= CURRENT_DATE - INTERVAL '30 days'
GROUP BY u.id, u.name
ORDER BY total_occurrences_registered DESC;

-- ============================================================================
-- 3. SUBQUERIES AND CTEs
-- ============================================================================

-- Students with above-average occurrences in their class
WITH class_avg AS (
  SELECT
    c.id as class_id,
    AVG(occurrence_count) as avg_occurrences
  FROM classes c
  LEFT JOIN (
    SELECT
      s.class_id,
      s.id as student_id,
      COUNT(o.id) as occurrence_count
    FROM students s
    LEFT JOIN occurrences o ON s.id = o.student_id
    WHERE s.deleted_at IS NULL
    GROUP BY s.class_id, s.id
  ) student_occurrences ON c.id = student_occurrences.class_id
  GROUP BY c.id
)
SELECT
  s.name as student_name,
  c.name as class_name,
  COUNT(o.id) as student_occurrences,
  ROUND(ca.avg_occurrences, 2) as class_average
FROM students s
INNER JOIN classes c ON s.class_id = c.id
LEFT JOIN occurrences o ON s.id = o.student_id
INNER JOIN class_avg ca ON c.id = ca.class_id
WHERE s.institution_id = 'institution-uuid-here'
  AND s.deleted_at IS NULL
GROUP BY s.id, s.name, c.name, ca.avg_occurrences
HAVING COUNT(o.id) > ca.avg_occurrences
ORDER BY student_occurrences DESC;

-- Student movement history with class names
WITH student_movements AS (
  SELECT
    sch.student_id,
    sch.moved_at,
    c_from.name as from_class,
    c_to.name as to_class,
    sch.reason,
    ROW_NUMBER() OVER (PARTITION BY sch.student_id ORDER BY sch.moved_at DESC) as movement_rank
  FROM student_class_history sch
  LEFT JOIN classes c_from ON sch.moved_from_class_id = c_from.id
  LEFT JOIN classes c_to ON sch.class_id = c_to.id
)
SELECT
  s.name as student_name,
  s.registration_number,
  sm.moved_at,
  sm.from_class,
  sm.to_class,
  sm.reason
FROM students s
INNER JOIN student_movements sm ON s.id = sm.student_id
WHERE s.institution_id = 'institution-uuid-here'
  AND sm.movement_rank <= 5  -- Last 5 movements per student
ORDER BY s.name, sm.moved_at DESC;

-- ============================================================================
-- 4. WINDOW FUNCTIONS
-- ============================================================================

-- Rank students by occurrence count within each class
SELECT
  c.name as class_name,
  s.name as student_name,
  COUNT(o.id) as occurrence_count,
  RANK() OVER (PARTITION BY c.id ORDER BY COUNT(o.id) DESC) as rank_in_class,
  PERCENT_RANK() OVER (PARTITION BY c.id ORDER BY COUNT(o.id)) as percentile_rank
FROM classes c
INNER JOIN students s ON c.id = s.class_id
LEFT JOIN occurrences o ON s.id = o.student_id
WHERE c.institution_id = 'institution-uuid-here'
  AND s.deleted_at IS NULL
GROUP BY c.id, c.name, s.id, s.name
ORDER BY c.name, occurrence_count DESC;

-- Occurrence trend over time (monthly breakdown)
SELECT
  DATE_TRUNC('month', o.occurred_at) as month,
  COUNT(o.id) as occurrence_count,
  COUNT(DISTINCT o.student_id) as affected_students,
  LAG(COUNT(o.id)) OVER (ORDER BY DATE_TRUNC('month', o.occurred_at)) as previous_month_count,
  COUNT(o.id) - LAG(COUNT(o.id)) OVER (ORDER BY DATE_TRUNC('month', o.occurred_at)) as month_over_month_change
FROM occurrences o
WHERE o.institution_id = 'institution-uuid-here'
  AND o.occurred_at >= CURRENT_DATE - INTERVAL '12 months'
GROUP BY DATE_TRUNC('month', o.occurred_at)
ORDER BY month DESC;

-- ============================================================================
-- 5. ADVANCED ANALYTICS
-- ============================================================================

-- Cohort analysis: Class performance comparison
SELECT
  c.academic_year,
  c.name as class_name,
  COUNT(DISTINCT s.id) as total_students,
  COUNT(o.id) as total_occurrences,
  ROUND(COUNT(o.id)::NUMERIC / NULLIF(COUNT(DISTINCT s.id), 0), 2) as occurrences_per_student,
  ROUND(
    100.0 * COUNT(DISTINCT CASE WHEN o.id IS NOT NULL THEN s.id END) /
    NULLIF(COUNT(DISTINCT s.id), 0),
    1
  ) as pct_students_with_occurrences
FROM classes c
LEFT JOIN students s ON c.id = s.class_id AND s.deleted_at IS NULL
LEFT JOIN occurrences o ON s.id = o.student_id
WHERE c.institution_id = 'institution-uuid-here'
GROUP BY c.id, c.academic_year, c.name
ORDER BY c.academic_year DESC, occurrences_per_student DESC;

-- Severity distribution by time of day
SELECT
  EXTRACT(HOUR FROM o.occurred_at) as hour_of_day,
  ot.severity,
  COUNT(o.id) as occurrence_count
FROM occurrences o
INNER JOIN occurrence_types ot ON o.occurrence_type_id = ot.id
WHERE o.institution_id = 'institution-uuid-here'
  AND o.occurred_at >= CURRENT_DATE - INTERVAL '90 days'
GROUP BY EXTRACT(HOUR FROM o.occurred_at), ot.severity
ORDER BY hour_of_day, ot.severity;

-- Identify at-risk students (multiple high-severity occurrences)
SELECT
  s.name as student_name,
  s.registration_number,
  c.name as class_name,
  COUNT(o.id) FILTER (WHERE ot.severity = 'high') as high_severity_count,
  COUNT(o.id) as total_occurrences,
  MAX(o.occurred_at) as last_occurrence_date,
  CASE
    WHEN COUNT(o.id) FILTER (WHERE ot.severity = 'high') >= 3 THEN 'Critical'
    WHEN COUNT(o.id) FILTER (WHERE ot.severity = 'high') >= 2 THEN 'High Risk'
    WHEN COUNT(o.id) >= 5 THEN 'Moderate Risk'
    ELSE 'Low Risk'
  END as risk_level
FROM students s
LEFT JOIN classes c ON s.class_id = c.id
LEFT JOIN occurrences o ON s.id = o.student_id
LEFT JOIN occurrence_types ot ON o.occurrence_type_id = ot.id
WHERE s.institution_id = 'institution-uuid-here'
  AND s.deleted_at IS NULL
  AND o.occurred_at >= CURRENT_DATE - INTERVAL '90 days'
GROUP BY s.id, s.name, s.registration_number, c.name
HAVING COUNT(o.id) > 0
ORDER BY high_severity_count DESC, total_occurrences DESC;

-- ============================================================================
-- 6. DATA QUALITY AND VALIDATION
-- ============================================================================

-- Find students without classes
SELECT
  s.id,
  s.name,
  s.registration_number,
  s.created_at
FROM students s
WHERE s.institution_id = 'institution-uuid-here'
  AND s.deleted_at IS NULL
  AND s.class_id IS NULL;

-- Find duplicate registration numbers
SELECT
  institution_id,
  registration_number,
  COUNT(*) as duplicate_count,
  ARRAY_AGG(name) as student_names
FROM students
WHERE deleted_at IS NULL
  AND registration_number IS NOT NULL
GROUP BY institution_id, registration_number
HAVING COUNT(*) > 1;

-- Audit trail: Recently deleted items
SELECT
  'student' as record_type,
  s.id,
  s.name,
  s.deleted_at,
  u.name as deleted_by_user
FROM students s
LEFT JOIN users u ON s.deleted_by = u.id
WHERE s.deleted_at IS NOT NULL
  AND s.deleted_at >= CURRENT_DATE - INTERVAL '30 days'

UNION ALL

SELECT
  'user' as record_type,
  usr.id,
  usr.name,
  usr.deleted_at,
  deleter.name as deleted_by_user
FROM users usr
LEFT JOIN users deleter ON usr.deleted_by = deleter.id
WHERE usr.deleted_at IS NOT NULL
  AND usr.deleted_at >= CURRENT_DATE - INTERVAL '30 days'

ORDER BY deleted_at DESC;

-- ============================================================================
-- 7. PERFORMANCE QUERIES
-- ============================================================================

-- Index usage analysis
SELECT
  schemaname,
  tablename,
  indexname,
  idx_scan as index_scans,
  idx_tup_read as tuples_read,
  idx_tup_fetch as tuples_fetched
FROM pg_stat_user_indexes
WHERE schemaname = 'public'
ORDER BY idx_scan DESC;

-- Table sizes
SELECT
  tablename,
  pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) as total_size,
  pg_size_pretty(pg_relation_size(schemaname||'.'||tablename)) as table_size,
  pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename) - pg_relation_size(schemaname||'.'||tablename)) as indexes_size
FROM pg_tables
WHERE schemaname = 'public'
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;

-- ============================================================================
-- END OF EXAMPLE QUERIES
-- ============================================================================
