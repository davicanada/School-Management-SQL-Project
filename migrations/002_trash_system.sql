-- ============================================================================
-- TRASH SYSTEM - School Management
-- ============================================================================
-- Date: 2025-10-27
-- Description: Implementation of a trash system (advanced soft delete)
-- ============================================================================

-- ============================================================================
-- PART 1: ADD TRASH FIELDS
-- ============================================================================

-- Add fields to users table (teachers)
ALTER TABLE users
ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMP NULL,
ADD COLUMN IF NOT EXISTS deleted_by UUID REFERENCES users(id) NULL;

-- Add fields to students table
ALTER TABLE students
ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMP NULL,
ADD COLUMN IF NOT EXISTS deleted_by UUID REFERENCES users(id) NULL;

-- Explanatory comments
COMMENT ON COLUMN users.deleted_at IS 'Date and time when the user was moved to the trash. NULL = not in trash';
COMMENT ON COLUMN users.deleted_by IS 'ID of the user (admin/master) who moved this record to the trash';
COMMENT ON COLUMN students.deleted_at IS 'Date and time when the student was moved to the trash. NULL = not in trash';
COMMENT ON COLUMN students.deleted_by IS 'ID of the user (admin/master) who moved this record to the trash';

-- ============================================================================
-- PART 2: CREATE INDEXES FOR PERFORMANCE
-- ============================================================================

-- Indexes to speed up queries filtering by deleted_at
CREATE INDEX IF NOT EXISTS idx_users_deleted_at ON users(deleted_at);
CREATE INDEX IF NOT EXISTS idx_students_deleted_at ON students(deleted_at);

-- Composite index for queries filtering by institution + deleted_at
CREATE INDEX IF NOT EXISTS idx_users_institution_deleted
ON users(institution_id, deleted_at)
WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_students_institution_deleted
ON students(institution_id, deleted_at)
WHERE deleted_at IS NULL;

-- ============================================================================
-- PART 3: UPDATE RLS POLICIES (Row Level Security)
-- ============================================================================

-- Note: The existing RLS policies will already work with the trash system
-- because the deleted_at field is only an additional filter at the application level.
-- But we will create specific policies to ensure security.

-- Policy: Only Master can permanently delete
DROP POLICY IF EXISTS "users_delete_master_only" ON users;
CREATE POLICY "users_delete_master_only" ON users
FOR DELETE USING (
  EXISTS (
    SELECT 1 FROM user_institutions
    WHERE user_id = auth.uid()
    AND role = 'master'
  )
);

DROP POLICY IF EXISTS "students_delete_policy" ON students;
CREATE POLICY "students_delete_policy" ON students
FOR DELETE USING (
  -- Only Master can permanently delete
  EXISTS (
    SELECT 1 FROM user_institutions ui
    WHERE ui.user_id = auth.uid()
    AND ui.role = 'master'
  )
  OR
  -- Or Admin of the same institution can delete (if no related data – checked in code)
  EXISTS (
    SELECT 1 FROM user_institutions ui
    WHERE ui.user_id = auth.uid()
    AND ui.institution_id = students.institution_id
    AND ui.role = 'admin'
  )
);

-- ============================================================================
-- PART 4: FUNCTION TO MOVE TO TRASH
-- ============================================================================

-- Helper function to move a user to the trash
CREATE OR REPLACE FUNCTION move_user_to_trash(
  p_user_id UUID,
  p_deleted_by UUID
)
RETURNS BOOLEAN AS $$
BEGIN
  UPDATE users
  SET
    deleted_at = NOW(),
    deleted_by = p_deleted_by,
    is_active = false  -- Ensure it also becomes inactive
  WHERE id = p_user_id;

  RETURN FOUND;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Helper function to restore user from trash
CREATE OR REPLACE FUNCTION restore_user_from_trash(
  p_user_id UUID
)
RETURNS BOOLEAN AS $$
BEGIN
  UPDATE users
  SET
    deleted_at = NULL,
    deleted_by = NULL,
    is_active = false  -- Returns as INACTIVE (admin must activate manually)
  WHERE id = p_user_id;

  RETURN FOUND;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Helper function to move a student to the trash
CREATE OR REPLACE FUNCTION move_student_to_trash(
  p_student_id UUID,
  p_deleted_by UUID
)
RETURNS BOOLEAN AS $$
BEGIN
  UPDATE students
  SET
    deleted_at = NOW(),
    deleted_by = p_deleted_by,
    is_active = false  -- Ensure it also becomes inactive
  WHERE id = p_student_id;

  RETURN FOUND;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Helper function to restore student from trash
CREATE OR REPLACE FUNCTION restore_student_from_trash(
  p_student_id UUID
)
RETURNS BOOLEAN AS $$
BEGIN
  UPDATE students
  SET
    deleted_at = NULL,
    deleted_by = NULL,
    is_active = false  -- Returns as INACTIVE (admin must activate manually)
  WHERE id = p_student_id;

  RETURN FOUND;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- PART 5: VIEW TO SIMPLIFY QUERIES
-- ============================================================================

-- View to list only active users (not in trash)
CREATE OR REPLACE VIEW active_users AS
SELECT * FROM users
WHERE deleted_at IS NULL;

-- View to list only users in trash
CREATE OR REPLACE VIEW trashed_users AS
SELECT * FROM users
WHERE deleted_at IS NOT NULL;

-- View to list only active students (not in trash)
CREATE OR REPLACE VIEW active_students AS
SELECT * FROM students
WHERE deleted_at IS NULL;

-- View to list only students in trash
CREATE OR REPLACE VIEW trashed_students AS
SELECT * FROM students
WHERE deleted_at IS NOT NULL;

-- ============================================================================
-- PART 6: AUTOMATIC CLEANUP (OPTIONAL)
-- ============================================================================

-- Function to permanently delete old records from trash
-- (Run manually or via cron job)
CREATE OR REPLACE FUNCTION cleanup_old_trash(
  p_days_old INTEGER DEFAULT 90
)
RETURNS TABLE(
  deleted_users_count INTEGER,
  deleted_students_count INTEGER
) AS $$
DECLARE
  v_users_count INTEGER;
  v_students_count INTEGER;
BEGIN
  -- Delete users in trash older than X days
  WITH deleted AS (
    DELETE FROM users
    WHERE deleted_at < NOW() - INTERVAL '1 day' * p_days_old
    AND deleted_at IS NOT NULL
    RETURNING *
  )
  SELECT COUNT(*) INTO v_users_count FROM deleted;

  -- Delete students in trash older than X days
  WITH deleted AS (
    DELETE FROM students
    WHERE deleted_at < NOW() - INTERVAL '1 day' * p_days_old
    AND deleted_at IS NOT NULL
    RETURNING *
  )
  SELECT COUNT(*) INTO v_students_count FROM deleted;

  RETURN QUERY SELECT v_users_count, v_students_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- USEFUL ADMIN COMMANDS
-- ============================================================================

-- View number of records in trash
-- SELECT COUNT(*) FROM users WHERE deleted_at IS NOT NULL;
-- SELECT COUNT(*) FROM students WHERE deleted_at IS NOT NULL;

-- View trash records with info on who deleted them
-- SELECT u.*, d.name as deleted_by_name
-- FROM users u
-- LEFT JOIN users d ON u.deleted_by = d.id
-- WHERE u.deleted_at IS NOT NULL;

-- Clean trash (delete records older than 90 days)
-- SELECT * FROM cleanup_old_trash(90);

-- ============================================================================
-- END OF SCRIPT
-- ============================================================================
