-- ============================================================================
-- DATABASE SCHEMA - Sistema de Gestão Escolar
-- ============================================================================
-- Database: PostgreSQL 17+ (Supabase)
-- Description: Multi-tenant school management system with RLS
-- Author: Data Analyst Portfolio
-- ============================================================================

-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ============================================================================
-- TABLE: institutions
-- ============================================================================
-- Core table for multi-tenancy. All schools/organizations in the system.
CREATE TABLE institutions (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name VARCHAR(255) NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

COMMENT ON TABLE institutions IS 'Educational institutions (schools) registered in the system';
COMMENT ON COLUMN institutions.id IS 'Unique identifier for the institution';
COMMENT ON COLUMN institutions.name IS 'Name of the educational institution';

-- ============================================================================
-- TABLE: users
-- ============================================================================
-- Users can be: master (super admin), admin, or professor
CREATE TABLE users (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email VARCHAR(255) UNIQUE NOT NULL,
  name VARCHAR(255) NOT NULL,
  role VARCHAR(50) NOT NULL DEFAULT 'professor' CHECK (role IN ('master', 'admin', 'professor')),
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  -- Trash system fields
  deleted_at TIMESTAMP NULL,
  deleted_by UUID REFERENCES users(id) NULL
);

COMMENT ON TABLE users IS 'System users (master, admin, professor)';
COMMENT ON COLUMN users.role IS 'Global user role: master (super admin), admin, or professor';
COMMENT ON COLUMN users.deleted_at IS 'Timestamp when user was moved to trash. NULL = not in trash';
COMMENT ON COLUMN users.deleted_by IS 'ID of user (admin/master) who moved this record to trash';

-- ============================================================================
-- TABLE: user_institutions
-- ============================================================================
-- Many-to-many relationship: users can belong to multiple institutions
-- with different roles in each
CREATE TABLE user_institutions (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  institution_id UUID NOT NULL REFERENCES institutions(id) ON DELETE CASCADE,
  role VARCHAR(50) NOT NULL CHECK (role IN ('admin', 'professor')),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  UNIQUE(user_id, institution_id)
);

COMMENT ON TABLE user_institutions IS 'N:N relationship between users and institutions with specific role';
COMMENT ON COLUMN user_institutions.role IS 'User role in this specific institution: admin or professor';

-- ============================================================================
-- TABLE: classes
-- ============================================================================
-- Academic classes/classrooms within institutions
CREATE TABLE classes (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  institution_id UUID NOT NULL REFERENCES institutions(id) ON DELETE CASCADE,
  name VARCHAR(255) NOT NULL,
  academic_year INTEGER NOT NULL,
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

COMMENT ON TABLE classes IS 'Academic classes within institutions by academic year';
COMMENT ON COLUMN classes.academic_year IS 'Year the class is active (e.g., 2024)';
COMMENT ON COLUMN classes.is_active IS 'Whether the class is currently active';

-- ============================================================================
-- TABLE: students
-- ============================================================================
-- Students enrolled in institutions
CREATE TABLE students (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  institution_id UUID NOT NULL REFERENCES institutions(id) ON DELETE CASCADE,
  class_id UUID REFERENCES classes(id) ON DELETE SET NULL,
  name VARCHAR(255) NOT NULL,
  registration_number VARCHAR(100),
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  -- Trash system fields
  deleted_at TIMESTAMP NULL,
  deleted_by UUID REFERENCES users(id) NULL
);

COMMENT ON TABLE students IS 'Students enrolled in institutions';
COMMENT ON COLUMN students.registration_number IS 'Student registration number (unique per institution)';
COMMENT ON COLUMN students.deleted_at IS 'Timestamp when student was moved to trash. NULL = not in trash';
COMMENT ON COLUMN students.deleted_by IS 'ID of user (admin/master) who moved this record to trash';

-- Ensure registration_number is unique per institution
ALTER TABLE students
ADD CONSTRAINT students_registration_number_institution_key
UNIQUE NULLS NOT DISTINCT (institution_id, registration_number);

-- ============================================================================
-- TABLE: student_class_history
-- ============================================================================
-- Tracks student movements between classes
CREATE TABLE student_class_history (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  student_id UUID NOT NULL REFERENCES students(id) ON DELETE CASCADE,
  class_id UUID REFERENCES classes(id) ON DELETE SET NULL,
  moved_from_class_id UUID REFERENCES classes(id) ON DELETE SET NULL,
  moved_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  reason TEXT
);

COMMENT ON TABLE student_class_history IS 'History of student movements between classes';
COMMENT ON COLUMN student_class_history.moved_at IS 'Timestamp when student was moved';
COMMENT ON COLUMN student_class_history.reason IS 'Reason for the class transfer';

-- ============================================================================
-- TABLE: occurrence_types
-- ============================================================================
-- Configurable types of disciplinary occurrences per institution
CREATE TABLE occurrence_types (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  institution_id UUID NOT NULL REFERENCES institutions(id) ON DELETE CASCADE,
  name VARCHAR(255) NOT NULL,
  severity VARCHAR(50) CHECK (severity IN ('low', 'medium', 'high')),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

COMMENT ON TABLE occurrence_types IS 'Configurable disciplinary occurrence types per institution';
COMMENT ON COLUMN occurrence_types.severity IS 'Severity level: low, medium, or high';

-- ============================================================================
-- TABLE: occurrences
-- ============================================================================
-- Disciplinary occurrence records
CREATE TABLE occurrences (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  institution_id UUID NOT NULL REFERENCES institutions(id) ON DELETE CASCADE,
  student_id UUID NOT NULL REFERENCES students(id) ON DELETE CASCADE,
  teacher_id UUID REFERENCES users(id) ON DELETE SET NULL,
  class_id UUID REFERENCES classes(id) ON DELETE SET NULL,
  occurrence_type_id UUID NOT NULL REFERENCES occurrence_types(id) ON DELETE CASCADE,
  description TEXT NOT NULL,
  occurred_at TIMESTAMP WITH TIME ZONE NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

COMMENT ON TABLE occurrences IS 'Disciplinary occurrence records for students';
COMMENT ON COLUMN occurrences.occurred_at IS 'Date/time when the occurrence happened (may differ from created_at)';
COMMENT ON COLUMN occurrences.teacher_id IS 'Teacher who registered the occurrence';

-- ============================================================================
-- TABLE: access_requests
-- ============================================================================
-- Requests for system access (institution/user creation)
CREATE TABLE access_requests (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  institution_id UUID REFERENCES institutions(id) ON DELETE CASCADE,
  user_id UUID REFERENCES users(id) ON DELETE SET NULL,
  approved_by UUID REFERENCES users(id) ON DELETE SET NULL,
  status VARCHAR(50) DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
  request_data JSONB,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  processed_at TIMESTAMP WITH TIME ZONE
);

COMMENT ON TABLE access_requests IS 'Requests for system access (institution/user creation)';
COMMENT ON COLUMN access_requests.status IS 'Request status: pending, approved, or rejected';
COMMENT ON COLUMN access_requests.request_data IS 'JSON data with request details';

-- ============================================================================
-- INDEXES FOR PERFORMANCE
-- ============================================================================

-- Foreign key indexes (CRITICAL for query performance)
CREATE INDEX idx_classes_institution_id ON classes(institution_id);
CREATE INDEX idx_students_institution_id ON students(institution_id);
CREATE INDEX idx_students_class_id ON students(class_id);
CREATE INDEX idx_occurrences_institution_id ON occurrences(institution_id);
CREATE INDEX idx_occurrences_student_id ON occurrences(student_id);
CREATE INDEX idx_occurrences_teacher_id ON occurrences(teacher_id);
CREATE INDEX idx_occurrences_class_id ON occurrences(class_id);
CREATE INDEX idx_occurrences_occurrence_type_id ON occurrences(occurrence_type_id);
CREATE INDEX idx_occurrence_types_institution_id ON occurrence_types(institution_id);
CREATE INDEX idx_student_class_history_student_id ON student_class_history(student_id);
CREATE INDEX idx_student_class_history_class_id ON student_class_history(class_id);
CREATE INDEX idx_student_class_history_moved_from_class_id ON student_class_history(moved_from_class_id);
CREATE INDEX idx_user_institutions_user_id ON user_institutions(user_id);
CREATE INDEX idx_user_institutions_institution_id ON user_institutions(institution_id);
CREATE INDEX idx_access_requests_institution_id ON access_requests(institution_id);
CREATE INDEX idx_access_requests_approved_by ON access_requests(approved_by);

-- Trash system indexes
CREATE INDEX idx_users_deleted_at ON users(deleted_at);
CREATE INDEX idx_students_deleted_at ON students(deleted_at);

-- Composite indexes for common queries
CREATE INDEX idx_users_institution_deleted ON users(institution_id, deleted_at) WHERE deleted_at IS NULL;
CREATE INDEX idx_students_institution_deleted ON students(institution_id, deleted_at) WHERE deleted_at IS NULL;
CREATE INDEX idx_classes_institution_year_active ON classes(institution_id, academic_year, is_active) WHERE is_active = true;
CREATE INDEX idx_occurrences_institution_date ON occurrences(institution_id, occurred_at DESC);
CREATE INDEX idx_access_requests_status ON access_requests(status) WHERE status = 'pending';
CREATE INDEX idx_student_class_history_moved_at ON student_class_history(moved_at DESC);
CREATE INDEX idx_students_class_active ON students(class_id, is_active) WHERE is_active = true;

-- ============================================================================
-- VIEWS FOR TRASH SYSTEM
-- ============================================================================

CREATE OR REPLACE VIEW active_users AS
SELECT * FROM users WHERE deleted_at IS NULL;

CREATE OR REPLACE VIEW trashed_users AS
SELECT * FROM users WHERE deleted_at IS NOT NULL;

CREATE OR REPLACE VIEW active_students AS
SELECT * FROM students WHERE deleted_at IS NULL;

CREATE OR REPLACE VIEW trashed_students AS
SELECT * FROM students WHERE deleted_at IS NOT NULL;

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

-- Function to move user to trash
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
    is_active = false
  WHERE id = p_user_id;

  RETURN FOUND;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to restore user from trash
CREATE OR REPLACE FUNCTION restore_user_from_trash(
  p_user_id UUID
)
RETURNS BOOLEAN AS $$
BEGIN
  UPDATE users
  SET
    deleted_at = NULL,
    deleted_by = NULL,
    is_active = false  -- Remains inactive until admin manually activates
  WHERE id = p_user_id;

  RETURN FOUND;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to move student to trash
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
    is_active = false
  WHERE id = p_student_id;

  RETURN FOUND;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to restore student from trash
CREATE OR REPLACE FUNCTION restore_student_from_trash(
  p_student_id UUID
)
RETURNS BOOLEAN AS $$
BEGIN
  UPDATE students
  SET
    deleted_at = NULL,
    deleted_by = NULL,
    is_active = false  -- Remains inactive until admin manually activates
  WHERE id = p_student_id;

  RETURN FOUND;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to cleanup old trash (90+ days)
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
  WITH deleted AS (
    DELETE FROM users
    WHERE deleted_at < NOW() - INTERVAL '1 day' * p_days_old
    AND deleted_at IS NOT NULL
    RETURNING *
  )
  SELECT COUNT(*) INTO v_users_count FROM deleted;

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
-- ROW LEVEL SECURITY (RLS) POLICIES
-- ============================================================================
-- Note: RLS policies are defined in migration files for better organization
-- See: database/migrations/001_database_architecture_fixes.sql
-- ============================================================================

-- Enable RLS on all tables
ALTER TABLE institutions ENABLE ROW LEVEL SECURITY;
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_institutions ENABLE ROW LEVEL SECURITY;
ALTER TABLE classes ENABLE ROW LEVEL SECURITY;
ALTER TABLE students ENABLE ROW LEVEL SECURITY;
ALTER TABLE student_class_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE occurrence_types ENABLE ROW LEVEL SECURITY;
ALTER TABLE occurrences ENABLE ROW LEVEL SECURITY;
ALTER TABLE access_requests ENABLE ROW LEVEL SECURITY;

-- ============================================================================
-- END OF SCHEMA
-- ============================================================================
