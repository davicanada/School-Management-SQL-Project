-- ============================================================================
-- DATABASE ARCHITECTURE FIXES – School Management
-- ============================================================================
-- Date: 2025-10-26
-- Description: SQL scripts to fix issues identified during analysis
-- IMPORTANT: Test in development environment before applying in production
-- ============================================================================

-- ============================================================================
-- PART 1: CRITICAL FIXES (EXECUTE FIRST)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1.1 – Create RLS policies for student_class_history
-- ----------------------------------------------------------------------------
-- Issue: Table has RLS enabled but no policies (data inaccessible)
-- Priority: CRITICAL

-- Allow SELECT for users from the same institution
CREATE POLICY "student_class_history_select" ON student_class_history
FOR SELECT USING (
  EXISTS (
    SELECT 1 FROM students s
    JOIN user_institutions ui ON s.institution_id = ui.institution_id
    WHERE s.id = student_class_history.student_id
    AND ui.user_id = auth.uid()
  )
);

-- Allow INSERT only for institution admins
CREATE POLICY "student_class_history_insert" ON student_class_history
FOR INSERT WITH CHECK (
  EXISTS (
    SELECT 1 FROM students s
    JOIN user_institutions ui ON s.institution_id = ui.institution_id
    WHERE s.id = student_id  -- student_id used during INSERT
    AND ui.user_id = auth.uid()
    AND ui.role = 'admin'
  )
);

-- Allow UPDATE only for institution admins
CREATE POLICY "student_class_history_update" ON student_class_history
FOR UPDATE USING (
  EXISTS (
    SELECT 1 FROM students s
    JOIN user_institutions ui ON s.institution_id = ui.institution_id
    WHERE s.id = student_class_history.student_id
    AND ui.user_id = auth.uid()
    AND ui.role = 'admin'
  )
);

-- Allow DELETE only for institution admins
CREATE POLICY "student_class_history_delete" ON student_class_history
FOR DELETE USING (
  EXISTS (
    SELECT 1 FROM students s
    JOIN user_institutions ui ON s.institution_id = ui.institution_id
    WHERE s.id = student_class_history.student_id
    AND ui.user_id = auth.uid()
    AND ui.role = 'admin'
  )
);

-- ----------------------------------------------------------------------------
-- 1.2 – Remove temporary development policies
-- ----------------------------------------------------------------------------
-- Issue: "Temporary dev policy" entries with unrestricted access (qualifier: true)
-- Priority: CRITICAL

DROP POLICY IF EXISTS "Temporary dev policy - users" ON users;
DROP POLICY IF EXISTS "Temporary dev policy - classes" ON classes;
DROP POLICY IF EXISTS "Temporary dev policy - students" ON students;
DROP POLICY IF EXISTS "Temporary dev policy - occurrences" ON occurrences;
DROP POLICY IF EXISTS "Temporary dev policy - occurrence_types" ON occurrence_types;

-- ----------------------------------------------------------------------------
-- 1.3 – Create indexes for critical foreign keys
-- ----------------------------------------------------------------------------
-- Issue: 11 foreign keys without indexes causing table scans during JOINs
-- Priority: CRITICAL

-- Indexes with CRITICAL impact
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_classes_institution_id
  ON classes(institution_id);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_occurrences_class_id
  ON occurrences(class_id);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_occurrences_occurrence_type_id
  ON occurrences(occurrence_type_id);

-- Indexes with HIGH impact
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_occurrence_types_institution_id
  ON occurrence_types(institution_id);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_student_class_history_student_id
  ON student_class_history(student_id);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_user_institutions_institution_id
  ON user_institutions(institution_id);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_access_requests_institution_id
  ON access_requests(institution_id);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_occurrences_teacher_id
  ON occurrences(teacher_id);

-- Indexes with MEDIUM/LOW impact (optional)
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_student_class_history_class_id
  ON student_class_history(class_id);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_student_class_history_moved_from_class_id
  ON student_class_history(moved_from_class_id);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_access_requests_approved_by
  ON access_requests(approved_by);


-- ============================================================================
-- PART 2: HIGH-PRIORITY FIXES
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 2.1 – Resolve redundancy in user_institutions
-- ----------------------------------------------------------------------------
-- Issue: Duplicate fields 'role' and 'role_in_institution'
-- Priority: HIGH

-- Step 1: Check for inconsistencies (run first)
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM user_institutions
    WHERE role IS DISTINCT FROM role_in_institution
  ) THEN
    RAISE EXCEPTION 'There are records with role != role_in_institution. Fix manually before continuing.';
  END IF;
END $$;

-- Step 2: Remove redundant column
ALTER TABLE user_institutions DROP COLUMN IF EXISTS role_in_institution;

-- Step 3: Ensure role is not null
UPDATE user_institutions SET role = 'professor' WHERE role IS NULL;
ALTER TABLE user_institutions ALTER COLUMN role SET NOT NULL;

-- ----------------------------------------------------------------------------
-- 2.2 – Add uniqueness constraints
-- ----------------------------------------------------------------------------
-- Issue: registration_number allows duplicates within the same institution
-- Priority: HIGH

-- Enforce unique student registration per institution
-- NULLS NOT DISTINCT allows only one NULL per institution
ALTER TABLE students
ADD CONSTRAINT IF NOT EXISTS students_registration_number_institution_key
UNIQUE NULLS NOT DISTINCT (institution_id, registration_number);

-- If registration_number must be mandatory, uncomment:
-- ALTER TABLE students ALTER COLUMN registration_number SET NOT NULL;

-- ----------------------------------------------------------------------------
-- 2.3 – Consolidate duplicated RLS policies
-- ----------------------------------------------------------------------------
-- Issue: Multiple permissive policies causing performance overhead
-- Priority: HIGH

-- === CLASSES ===
DROP POLICY IF EXISTS "Allow read classes" ON classes;

CREATE POLICY "classes_select_policy" ON classes
FOR SELECT USING (
  -- Masters can view everything
  EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role = 'master')
  OR
  -- Users can view classes from their institutions
  institution_id IN (
    SELECT institution_id FROM user_institutions WHERE user_id = auth.uid()
  )
);

CREATE POLICY "classes_insert_policy" ON classes
FOR INSERT WITH CHECK (
  -- Only institution admins can create classes
  institution_id IN (
    SELECT institution_id FROM user_institutions
    WHERE user_id = auth.uid() AND role = 'admin'
  )
);

CREATE POLICY "classes_update_policy" ON classes
FOR UPDATE USING (
  -- Only institution admins can update classes
  institution_id IN (
    SELECT institution_id FROM user_institutions
    WHERE user_id = auth.uid() AND role = 'admin'
  )
);

CREATE POLICY "classes_delete_policy" ON classes
FOR DELETE USING (
  -- Only institution admins can delete classes
  institution_id IN (
    SELECT institution_id FROM user_institutions
    WHERE user_id = auth.uid() AND role = 'admin'
  )
);

-- === OCCURRENCE_TYPES ===
DROP POLICY IF EXISTS "Allow read occurrence_types" ON occurrence_types;

CREATE POLICY "occurrence_types_select_policy" ON occurrence_types
FOR SELECT USING (
  EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role = 'master')
  OR
  institution_id IN (
    SELECT institution_id FROM user_institutions WHERE user_id = auth.uid()
  )
);

CREATE POLICY "occurrence_types_insert_policy" ON occurrence_types
FOR INSERT WITH CHECK (
  institution_id IN (
    SELECT institution_id FROM user_institutions
    WHERE user_id = auth.uid() AND role = 'admin'
  )
);

CREATE POLICY "occurrence_types_update_policy" ON occurrence_types
FOR UPDATE USING (
  institution_id IN (
    SELECT institution_id FROM user_institutions
    WHERE user_id = auth.uid() AND role = 'admin'
  )
);

CREATE POLICY "occurrence_types_delete_policy" ON occurrence_types
FOR DELETE USING (
  institution_id IN (
    SELECT institution_id FROM user_institutions
    WHERE user_id = auth.uid() AND role = 'admin'
  )
);

-- === STUDENTS ===
DROP POLICY IF EXISTS "Allow read students" ON students;

CREATE POLICY "students_select_policy" ON students
FOR SELECT USING (
  EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role = 'master')
  OR
  institution_id IN (
    SELECT institution_id FROM user_institutions WHERE user_id = auth.uid()
  )
);

CREATE POLICY "students_insert_policy" ON students
FOR INSERT WITH CHECK (
  institution_id IN (
    SELECT institution_id FROM user_institutions
    WHERE user_id = auth.uid() AND role = 'admin'
  )
);

CREATE POLICY "students_update_policy" ON students
FOR UPDATE USING (
  institution_id IN (
    SELECT institution_id FROM user_institutions
    WHERE user_id = auth.uid() AND role = 'admin'
  )
);

CREATE POLICY "students_delete_policy" ON students
FOR DELETE USING (
  institution_id IN (
    SELECT institution_id FROM user_institutions
    WHERE user_id = auth.uid() AND role = 'admin'
  )
);

-- === OCCURRENCES ===
DROP POLICY IF EXISTS "Allow insert occurrences" ON occurrences;
DROP POLICY IF EXISTS "Allow select occurrences" ON occurrences;

CREATE POLICY "occurrences_select_policy" ON occurrences
FOR SELECT USING (
  EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role = 'master')
  OR
  institution_id IN (
    SELECT institution_id FROM user_institutions WHERE user_id = auth.uid()
  )
);

CREATE POLICY "occurrences_insert_policy" ON occurrences
FOR INSERT WITH CHECK (
  -- Teachers and admins can create occurrences in their institution
  institution_id IN (
    SELECT institution_id FROM user_institutions WHERE user_id = auth.uid()
  )
  AND teacher_id = auth.uid()  -- Only the user themself as teacher
);

CREATE POLICY "occurrences_update_policy" ON occurrences
FOR UPDATE USING (
  -- Only the teacher who created it, or an institution admin
  (teacher_id = auth.uid())
  OR
  (institution_id IN (
    SELECT institution_id FROM user_institutions
    WHERE user_id = auth.uid() AND role = 'admin'
  ))
);

CREATE POLICY "occurrences_delete_policy" ON occurrences
FOR DELETE USING (
  -- Only institution admins may delete
  institution_id IN (
    SELECT institution_id FROM user_institutions
    WHERE user_id = auth.uid() AND role = 'admin'
  )
);

-- === USER_INSTITUTIONS ===
DROP POLICY IF EXISTS "Allow insert user_institutions" ON user_institutions;
DROP POLICY IF EXISTS "Master can insert user_institutions" ON user_institutions;

CREATE POLICY "user_institutions_select_policy" ON user_institutions
FOR SELECT USING (
  -- Masters see everything
  EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role = 'master')
  OR
  -- Admins see records from their own institution
  (institution_id IN (
    SELECT institution_id FROM user_institutions
    WHERE user_id = auth.uid() AND role = 'admin'
  ))
  OR
  -- Users see their own associations
  user_id = auth.uid()
);

CREATE POLICY "user_institutions_insert_policy" ON user_institutions
FOR INSERT WITH CHECK (
  -- Masters may insert any association
  EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role = 'master')
  OR
  -- Admins may add users to their institutions
  (institution_id IN (
    SELECT institution_id FROM user_institutions
    WHERE user_id = auth.uid() AND role = 'admin'
  ))
);

CREATE POLICY "user_institutions_delete_policy" ON user_institutions
FOR DELETE USING (
  EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role = 'master')
  OR
  (institution_id IN (
    SELECT institution_id FROM user_institutions
    WHERE user_id = auth.uid() AND role = 'admin'
  ))
);


-- ============================================================================
-- PART 3: PERFORMANCE IMPROVEMENTS (MEDIUM PRIORITY)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 3.1 – Composite indexes for common queries
-- ----------------------------------------------------------------------------

-- For listing active classes by institution and year
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_classes_institution_year_active
  ON classes(institution_id, academic_year, is_active)
  WHERE is_active = true;

-- For occurrence reports by period and institution
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_occurrences_institution_date
  ON occurrences(institution_id, occurred_at DESC);

-- To fetch pending access requests
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_access_requests_status
  ON access_requests(status)
  WHERE status = 'pending';

-- For student class movement history by date
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_student_class_history_moved_at
  ON student_class_history(moved_at DESC);

-- To fetch active students by class
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_students_class_active
  ON students(class_id, is_active)
  WHERE is_active = true;

-- ----------------------------------------------------------------------------
-- 3.2 – Define appropriate ON DELETE constraints
-- ----------------------------------------------------------------------------
-- IMPORTANT: Review business rules before applying

-- Student movement: allow SET NULL if class is deleted
ALTER TABLE student_class_history
DROP CONSTRAINT IF EXISTS student_class_history_class_id_fkey,
ADD CONSTRAINT student_class_history_class_id_fkey
FOREIGN KEY (class_id) REFERENCES classes(id) ON DELETE SET NULL;

ALTER TABLE student_class_history
DROP CONSTRAINT IF EXISTS student_class_history_moved_from_class_id_fkey,
ADD CONSTRAINT student_class_history_moved_from_class_id_fkey
FOREIGN KEY (moved_from_class_id) REFERENCES classes(id) ON DELETE SET NULL;

-- Occurrences: keep historical record even if teacher is deleted
ALTER TABLE occurrences
DROP CONSTRAINT IF EXISTS occurrences_teacher_id_fkey,
ADD CONSTRAINT occurrences_teacher_id_fkey
FOREIGN KEY (teacher_id) REFERENCES users(id) ON DELETE SET NULL;

-- Students: define CASCADE or SET NULL depending on business rules
-- Option A: SET NULL (student becomes unassigned)
-- ALTER TABLE students
-- DROP CONSTRAINT IF EXISTS students_class_id_fkey,
-- ADD CONSTRAINT students_class_id_fkey
-- FOREIGN KEY (class_id) REFERENCES classes(id) ON DELETE SET NULL;

-- Option B: RESTRICT (prevents deleting classes with assigned students)
-- ALTER TABLE students
-- DROP CONSTRAINT IF EXISTS students_class_id_fkey,
-- ADD CONSTRAINT students_class_id_fkey
-- FOREIGN KEY (class_id) REFERENCES classes(id) ON DELETE RESTRICT;


-- ============================================================================
-- PART 4: CLEANUP AND OPTIMIZATION (LOW PRIORITY)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 4.1 – Remove unused/duplicate indexes
-- ----------------------------------------------------------------------------
-- IMPORTANT: Evaluate after production data is available
-- Email already has UNIQUE index; extra index unnecessary

DROP INDEX CONCURRENTLY IF EXISTS idx_users_email;

-- ----------------------------------------------------------------------------
-- 4.2 – Add comments for documentation
-- ----------------------------------------------------------------------------

COMMENT ON TABLE institutions IS 'Educational institutions registered in the system';
COMMENT ON TABLE users IS 'System users (master, admin, teacher)';
COMMENT ON TABLE user_institutions IS 'Many-to-many relationship between users and institutions with specific roles';
COMMENT ON TABLE classes IS 'Institution classes for each academic year';
COMMENT ON TABLE students IS 'Students enrolled in the institutions';
COMMENT ON TABLE student_class_history IS 'Student movement history between classes';
COMMENT ON TABLE occurrence_types IS 'Configurable disciplinary occurrence types per institution';
COMMENT ON TABLE occurrences IS 'Disciplinary occurrence records for students';
COMMENT ON TABLE access_requests IS 'System access requests (institution/user creation)';

COMMENT ON COLUMN users.role IS 'Global user role: master (super admin), admin, or teacher';
COMMENT ON COLUMN user_institutions.role IS 'User role within a specific institution: admin or teacher';
COMMENT ON COLUMN students.registration_number IS 'Student registration number (unique per institution)';
COMMENT ON COLUMN occurrences.occurred_at IS 'Date/time when the occurrence took place (may differ from created_at)';

-- ----------------------------------------------------------------------------
-- 4.3 – Enable useful extensions (if needed)
-- ----------------------------------------------------------------------------

-- For full-text search in Portuguese
-- CREATE EXTENSION IF NOT EXISTS unaccent;
-- CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- For audit logging
-- CREATE EXTENSION IF NOT EXISTS pgaudit;

-- For scheduled jobs (reports, cleanup)
-- CREATE EXTENSION IF NOT EXISTS pg_cron;


-- ============================================================================
-- POST-APPLICATION CHECKS
-- ============================================================================

-- Check RLS policies in student_class_history
SELECT schemaname, tablename, policyname, cmd
FROM pg_policies
WHERE tablename = 'student_class_history'
ORDER BY cmd;

-- Check created indexes
SELECT schemaname, tablename, indexname
FROM pg_indexes
WHERE schemaname = 'public'
ORDER BY tablename, indexname;

-- Check foreign key constraints
SELECT
  tc.table_name,
  tc.constraint_name,
  kcu.column_name,
  ccu.table_name AS foreign_table_name,
  ccu.column_name AS foreign_column_name,
  rc.delete_rule
FROM information_schema.table_constraints tc
JOIN information_schema.key_column_usage kcu
  ON tc.constraint_name = kcu.constraint_name
JOIN information_schema.constraint_column_usage ccu
  ON ccu.constraint_name = tc.constraint_name
LEFT JOIN information_schema.referential_constraints rc
  ON tc.constraint_name = rc.constraint_name
WHERE tc.table_schema = 'public'
  AND tc.constraint_type = 'FOREIGN KEY'
ORDER BY tc.table_name, tc.constraint_name;

-- Check tables with RLS enabled but without policies
SELECT schemaname, tablename, rowsecurity
FROM pg_tables
WHERE schemaname = 'public'
  AND rowsecurity = true
  AND tablename NOT IN (
    SELECT DISTINCT tablename FROM pg_policies WHERE schemaname = 'public'
  );

-- ============================================================================
-- END OF SCRIPTS
-- ============================================================================
