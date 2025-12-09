# School-Management-SQL-Project
This database powers a comprehensive school management system with support for multiple institutions, student tracking, disciplinary occurrences, and role-based access control. Built on PostgreSQL 17+ and leveraging Supabase's authentication and Row Level Security (RLS) features.

## Key Features

- **Multi-tenancy**: Support for multiple educational institutions in a single database
- **Row Level Security (RLS)**: Fine-grained access control at the database level
- **Soft Delete System**: Trash/recycle bin functionality with audit trails
- **Performance Optimized**: Strategic indexes including composite and partial indexes
- **Type Safety**: Full PostgreSQL type system with constraints and validations
- **Audit Trail**: Comprehensive tracking of data changes and deletions

## Database Schema

### Core Tables

#### 1. **institutions**
Central table for multi-tenancy. Each school/organization is an institution.

```sql
Key columns: id, name, created_at, updated_at
```

#### 2. **users**
System users with three role levels:
- `master`: Super administrator (full system access)
- `admin`: Institution administrator
- `professor`: Teacher/educator

```sql
Key columns: id, email, name, role, is_active, deleted_at, deleted_by
Features: Soft delete support, references auth.users
```

#### 3. **user_institutions** (Many-to-Many)
Links users to institutions with specific roles per institution.

```sql
Key columns: user_id, institution_id, role
Constraint: User can have different roles in different institutions
```

#### 4. **classes**
Academic classes/classrooms within institutions.

```sql
Key columns: id, institution_id, name, academic_year, is_active
```

#### 5. **students**
Students enrolled in institutions.

```sql
Key columns: id, institution_id, class_id, name, registration_number
Features: Soft delete, unique registration per institution
```

#### 6. **student_class_history**
Tracks student movements between classes over time.

```sql
Key columns: student_id, class_id, moved_from_class_id, moved_at, reason
```

#### 7. **occurrence_types**
Configurable disciplinary occurrence types per institution.

```sql
Key columns: id, institution_id, name, severity (low/medium/high)
```

#### 8. **occurrences**
Disciplinary occurrence records linked to students.

```sql
Key columns: id, student_id, teacher_id, occurrence_type_id, occurred_at
```

#### 9. **access_requests**
System access requests for institution/user creation.

```sql
Key columns: id, status (pending/approved/rejected), request_data (JSONB)
```

## Architecture Diagram

```
┌─────────────────┐
│  institutions   │
└────────┬────────┘
         │
         ├─────────────────────────────────────┐
         │                                     │
    ┌────▼──────┐                      ┌──────▼───────┐
    │  classes  │                      │    users     │
    └─────┬─────┘                      └──────┬───────┘
          │                                   │
          │         ┌────────────────────────┴────────┐
          │         │                                  │
     ┌────▼─────────▼──┐                    ┌─────────▼──────────┐
     │    students      │                    │ user_institutions  │
     └────┬─────────────┘                    └────────────────────┘
          │
          ├──────────────────┬────────────────────┐
          │                  │                    │
  ┌───────▼────────┐  ┌──────▼────────┐  ┌───────▼──────────┐
  │  occurrences   │  │student_class_ │  │  (other tables)  │
  │                │  │   history     │  │                  │
  └────────────────┘  └───────────────┘  └──────────────────┘
          │
          │
  ┌───────▼────────────┐
  │ occurrence_types   │
  └────────────────────┘
```

## Performance Optimizations

### Indexes

The schema includes **23 strategic indexes** for optimal query performance:

**Critical Foreign Key Indexes:**
- `idx_classes_institution_id`
- `idx_students_institution_id`, `idx_students_class_id`
- `idx_occurrences_*` (institution, student, teacher, class, type)

**Composite Indexes for Common Queries:**
- `idx_classes_institution_year_active` - Active classes by institution/year
- `idx_occurrences_institution_date` - Time-series occurrence queries
- `idx_students_class_active` - Active students per class

**Partial Indexes for Filtered Queries:**
- `idx_users_institution_deleted WHERE deleted_at IS NULL`
- `idx_access_requests_status WHERE status = 'pending'`

### Query Optimization Examples

See `examples/queries.sql` for:
- Complex joins and aggregations
- Window functions for analytics
- CTEs for readable complex queries
- Performance monitoring queries

## Security Model

### Row Level Security (RLS)

All tables have RLS enabled with policies enforcing:

1. **Institution Isolation**: Users only see data from their institutions
2. **Role-Based Access**:
   - `master`: Full access across all institutions
   - `admin`: Full access within their institution(s)
   - `professor`: Read access, limited write access

3. **Soft Delete Protection**: Only masters can permanently delete records

Example policy:
```sql
CREATE POLICY "students_select_policy" ON students
FOR SELECT USING (
  EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role = 'master')
  OR
  institution_id IN (
    SELECT institution_id FROM user_institutions WHERE user_id = auth.uid()
  )
);
```

## Soft Delete System (Trash/Recycle Bin)

### Features

- **Audit Trail**: Tracks who deleted records and when
- **Restore Capability**: Deleted records can be restored
- **Auto-Cleanup**: Function to permanently delete records older than 90 days

### Implementation

```sql
-- Tables with soft delete: users, students
deleted_at TIMESTAMP NULL
deleted_by UUID REFERENCES users(id)

-- Helper functions
move_user_to_trash(user_id, deleted_by)
restore_user_from_trash(user_id)
move_student_to_trash(student_id, deleted_by)
restore_student_from_trash(student_id)
cleanup_old_trash(days_old)
```

### Views for Easy Querying

```sql
active_users        -- WHERE deleted_at IS NULL
trashed_users       -- WHERE deleted_at IS NOT NULL
active_students     -- WHERE deleted_at IS NULL
trashed_students    -- WHERE deleted_at IS NOT NULL
```

## Migrations

Database changes are tracked in versioned migration files:

| File | Description |
|------|-------------|
| `001_database_architecture_fixes.sql` | Core schema fixes: RLS policies, indexes, constraints |
| `002_trash_system.sql` | Soft delete implementation with functions and views |

### Applying Migrations

```bash
# Using Supabase CLI
supabase db push

# Or manually in Supabase SQL Editor
# Copy and paste migration file contents
```

## Example Queries

The `examples/queries.sql` file demonstrates:

1. **Basic Queries**: Student lists, class rosters
2. **Joins & Aggregations**: Occurrence reports, teacher activity
3. **CTEs & Subqueries**: Above-average analysis, movement history
4. **Window Functions**: Rankings, percentiles, trend analysis
5. **Advanced Analytics**: Cohort analysis, risk assessment, time patterns
6. **Data Quality**: Duplicate detection, validation queries
7. **Performance Monitoring**: Index usage, table sizes

## Data Validation & Constraints

### Unique Constraints
- `students.registration_number` unique per institution (NULLS NOT DISTINCT)
- `users.email` globally unique
- `user_institutions(user_id, institution_id)` unique pair

### Check Constraints
```sql
users.role        CHECK (role IN ('master', 'admin', 'professor'))
user_institutions.role CHECK (role IN ('admin', 'professor'))
occurrence_types.severity CHECK (severity IN ('low', 'medium', 'high'))
access_requests.status CHECK (status IN ('pending', 'approved', 'rejected'))
```

### Foreign Key Actions
- `ON DELETE CASCADE`: institution deletion removes all related data
- `ON DELETE SET NULL`: preserve historical data (teacher_id in occurrences)
- `ON DELETE RESTRICT`: prevent deletion with dependencies

## Best Practices

### 1. Always Filter by Institution
```sql
-- Good
WHERE institution_id = 'uuid' AND deleted_at IS NULL

-- Bad (bypasses RLS, causes table scans)
WHERE deleted_at IS NULL
```

### 2. Use Indexes Effectively
```sql
-- Leverages idx_classes_institution_year_active
WHERE institution_id = 'uuid' AND academic_year = 2024 AND is_active = true

-- Also benefits from partial index optimization
```

### 3. Leverage Views for Common Patterns
```sql
-- Instead of always filtering deleted_at
SELECT * FROM active_students WHERE class_id = 'uuid';
```

### 4. Use Prepared Statements
```sql
-- Prevents SQL injection, improves performance
PREPARE get_student AS
SELECT * FROM students WHERE id = $1 AND deleted_at IS NULL;
```

## Database Statistics

### Approximate Scale (Development)
- 9 core tables
- 23 performance indexes
- 4 helper functions
- 4 convenience views
- 20+ RLS policies

### Expected Production Capacity
- Supports 100+ institutions
- 10,000+ students per institution
- Efficient querying with current index strategy
- Horizontal scaling via Supabase infrastructure

## Development Tools

### Supabase Integration
```typescript
// TypeScript client with type safety
import { createClient } from '@supabase/supabase-js'

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL,
  process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY
)

// RLS enforced automatically
const { data: students } = await supabase
  .from('students')
  .select('*, classes(*)')
  .eq('is_active', true)
```

### Type Generation
```bash
# Generate TypeScript types from database
supabase gen types typescript --local > types/database.ts
```

## Monitoring & Maintenance

### Health Checks
```sql
-- Check for tables without RLS policies
SELECT schemaname, tablename, rowsecurity
FROM pg_tables
WHERE schemaname = 'public' AND rowsecurity = false;

-- Find missing indexes on foreign keys
-- (Use query from examples/queries.sql)
```

### Regular Maintenance
```sql
-- Clean up old trash (run monthly)
SELECT * FROM cleanup_old_trash(90);

-- Analyze query performance
EXPLAIN ANALYZE [your_query];

-- Update table statistics
ANALYZE students, occurrences, classes;
```

## Future Enhancements

Potential improvements for production deployment:

- [ ] Partitioning for `occurrences` table (by date)
- [ ] Full-text search on student names (pg_trgm extension)
- [ ] Materialized views for dashboard analytics
- [ ] Automated backup policies
- [ ] Read replicas for reporting queries

## Technical Stack

- **Database**: PostgreSQL 17.4
- **Platform**: Supabase
- **Region**: South America East (sa-east-1)
- **Extensions**: uuid-ossp, pgcrypto
- **Security**: Row Level Security (RLS)
- **Authentication**: Supabase Auth integration

## Documentation

- **Schema Definition**: `schema.sql`
- **Migration Files**: `migrations/*.sql`
- **Example Queries**: `examples/queries.sql`
- **This README**: Architecture and best practices

## License & Attribution

Database schema designed for educational management system.
Created as part of a data analyst portfolio project.

---

**Last Updated**: December 2025
**Database Version**: PostgreSQL 17.4.1.074
**Schema Version**: 2.0
