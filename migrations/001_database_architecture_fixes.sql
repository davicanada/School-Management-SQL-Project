-- ============================================================================
-- DATABASE ARCHITECTURE FIXES - Gestão Escolar
-- ============================================================================
-- Data: 2025-10-26
-- Descrição: Scripts SQL para corrigir problemas identificados na análise
-- IMPORTANTE: Testar em ambiente de desenvolvimento antes de aplicar em produção
-- ============================================================================

-- ============================================================================
-- PARTE 1: CORREÇÕES CRÍTICAS (EXECUTAR PRIMEIRO)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1.1 - Criar políticas RLS para student_class_history
-- ----------------------------------------------------------------------------
-- Problema: Tabela tem RLS habilitado mas sem políticas (dados inacessíveis)
-- Prioridade: CRÍTICA

-- Permitir SELECT para usuários da mesma instituição
CREATE POLICY "student_class_history_select" ON student_class_history
FOR SELECT USING (
  EXISTS (
    SELECT 1 FROM students s
    JOIN user_institutions ui ON s.institution_id = ui.institution_id
    WHERE s.id = student_class_history.student_id
    AND ui.user_id = auth.uid()
  )
);

-- Permitir INSERT apenas para admins da instituição
CREATE POLICY "student_class_history_insert" ON student_class_history
FOR INSERT WITH CHECK (
  EXISTS (
    SELECT 1 FROM students s
    JOIN user_institutions ui ON s.institution_id = ui.institution_id
    WHERE s.id = student_id  -- student_id do INSERT
    AND ui.user_id = auth.uid()
    AND ui.role = 'admin'
  )
);

-- Permitir UPDATE apenas para admins da instituição
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

-- Permitir DELETE apenas para admins da instituição
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
-- 1.2 - Remover políticas temporárias de desenvolvimento
-- ----------------------------------------------------------------------------
-- Problema: Políticas "Temporary dev policy" com acesso irrestrito (qual: true)
-- Prioridade: CRÍTICA

DROP POLICY IF EXISTS "Temporary dev policy - users" ON users;
DROP POLICY IF EXISTS "Temporary dev policy - classes" ON classes;
DROP POLICY IF EXISTS "Temporary dev policy - students" ON students;
DROP POLICY IF EXISTS "Temporary dev policy - occurrences" ON occurrences;
DROP POLICY IF EXISTS "Temporary dev policy - occurrence_types" ON occurrence_types;

-- ----------------------------------------------------------------------------
-- 1.3 - Criar índices para foreign keys críticas
-- ----------------------------------------------------------------------------
-- Problema: 11 foreign keys sem índices causando table scans em JOINs
-- Prioridade: CRÍTICA

-- Índices com impacto CRÍTICO
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_classes_institution_id
  ON classes(institution_id);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_occurrences_class_id
  ON occurrences(class_id);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_occurrences_occurrence_type_id
  ON occurrences(occurrence_type_id);

-- Índices com impacto ALTO
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

-- Índices com impacto MÉDIO/BAIXO (considerar criar)
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_student_class_history_class_id
  ON student_class_history(class_id);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_student_class_history_moved_from_class_id
  ON student_class_history(moved_from_class_id);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_access_requests_approved_by
  ON access_requests(approved_by);


-- ============================================================================
-- PARTE 2: CORREÇÕES DE ALTA PRIORIDADE
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 2.1 - Resolver redundância em user_institutions
-- ----------------------------------------------------------------------------
-- Problema: Campos 'role' e 'role_in_institution' duplicados
-- Prioridade: ALTA

-- Passo 1: Verificar se há inconsistências (executar primeiro)
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM user_institutions
    WHERE role IS DISTINCT FROM role_in_institution
  ) THEN
    RAISE EXCEPTION 'Existem registros com role != role_in_institution. Corrija manualmente antes de continuar.';
  END IF;
END $$;

-- Passo 2: Remover coluna redundante
ALTER TABLE user_institutions DROP COLUMN IF EXISTS role_in_institution;

-- Passo 3: Garantir que role não seja nulo
UPDATE user_institutions SET role = 'professor' WHERE role IS NULL;
ALTER TABLE user_institutions ALTER COLUMN role SET NOT NULL;

-- ----------------------------------------------------------------------------
-- 2.2 - Adicionar constraints de unicidade
-- ----------------------------------------------------------------------------
-- Problema: registration_number permite duplicatas na mesma instituição
-- Prioridade: ALTA

-- Garantir unicidade de matrícula por instituição
-- NULLS NOT DISTINCT permite apenas um NULL por instituição
ALTER TABLE students
ADD CONSTRAINT IF NOT EXISTS students_registration_number_institution_key
UNIQUE NULLS NOT DISTINCT (institution_id, registration_number);

-- Se registration_number deve ser obrigatório, descomentar:
-- ALTER TABLE students ALTER COLUMN registration_number SET NOT NULL;

-- ----------------------------------------------------------------------------
-- 2.3 - Consolidar políticas RLS duplicadas
-- ----------------------------------------------------------------------------
-- Problema: Múltiplas políticas permissivas causando overhead de performance
-- Prioridade: ALTA

-- === CLASSES ===
-- Consolidar "Allow read classes" + políticas temporárias
DROP POLICY IF EXISTS "Allow read classes" ON classes;

CREATE POLICY "classes_select_policy" ON classes
FOR SELECT USING (
  -- Masters podem ver tudo
  EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role = 'master')
  OR
  -- Usuários podem ver turmas de suas instituições
  institution_id IN (
    SELECT institution_id FROM user_institutions WHERE user_id = auth.uid()
  )
);

CREATE POLICY "classes_insert_policy" ON classes
FOR INSERT WITH CHECK (
  -- Apenas admins da instituição podem criar turmas
  institution_id IN (
    SELECT institution_id FROM user_institutions
    WHERE user_id = auth.uid() AND role = 'admin'
  )
);

CREATE POLICY "classes_update_policy" ON classes
FOR UPDATE USING (
  -- Apenas admins da instituição podem atualizar turmas
  institution_id IN (
    SELECT institution_id FROM user_institutions
    WHERE user_id = auth.uid() AND role = 'admin'
  )
);

CREATE POLICY "classes_delete_policy" ON classes
FOR DELETE USING (
  -- Apenas admins da instituição podem deletar turmas
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
  -- Professores e admins podem criar ocorrências em suas instituições
  institution_id IN (
    SELECT institution_id FROM user_institutions WHERE user_id = auth.uid()
  )
  AND teacher_id = auth.uid()  -- Apenas o próprio usuário como professor
);

CREATE POLICY "occurrences_update_policy" ON occurrences
FOR UPDATE USING (
  -- Apenas o professor que criou ou admin da instituição
  (teacher_id = auth.uid())
  OR
  (institution_id IN (
    SELECT institution_id FROM user_institutions
    WHERE user_id = auth.uid() AND role = 'admin'
  ))
);

CREATE POLICY "occurrences_delete_policy" ON occurrences
FOR DELETE USING (
  -- Apenas admins da instituição podem deletar
  institution_id IN (
    SELECT institution_id FROM user_institutions
    WHERE user_id = auth.uid() AND role = 'admin'
  )
);

-- === USER_INSTITUTIONS ===
-- Consolidar políticas duplicadas de INSERT
DROP POLICY IF EXISTS "Allow insert user_institutions" ON user_institutions;
DROP POLICY IF EXISTS "Master can insert user_institutions" ON user_institutions;

CREATE POLICY "user_institutions_select_policy" ON user_institutions
FOR SELECT USING (
  -- Masters veem tudo
  EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role = 'master')
  OR
  -- Admins veem da própria instituição
  (institution_id IN (
    SELECT institution_id FROM user_institutions
    WHERE user_id = auth.uid() AND role = 'admin'
  ))
  OR
  -- Usuários veem suas próprias associações
  user_id = auth.uid()
);

CREATE POLICY "user_institutions_insert_policy" ON user_institutions
FOR INSERT WITH CHECK (
  -- Masters podem inserir qualquer associação
  EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role = 'master')
  OR
  -- Admins podem adicionar usuários em suas instituições
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
-- PARTE 3: MELHORIAS DE PERFORMANCE (PRIORIDADE MÉDIA)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 3.1 - Índices compostos para queries comuns
-- ----------------------------------------------------------------------------

-- Para listagem de turmas ativas por instituição e ano
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_classes_institution_year_active
  ON classes(institution_id, academic_year, is_active)
  WHERE is_active = true;

-- Para relatórios de ocorrências por período e instituição
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_occurrences_institution_date
  ON occurrences(institution_id, occurred_at DESC);

-- Para buscar solicitações pendentes
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_access_requests_status
  ON access_requests(status)
  WHERE status = 'pending';

-- Para histórico de movimentação de alunos por data
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_student_class_history_moved_at
  ON student_class_history(moved_at DESC);

-- Para buscar alunos ativos por turma
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_students_class_active
  ON students(class_id, is_active)
  WHERE is_active = true;

-- ----------------------------------------------------------------------------
-- 3.2 - Definir constraints ON DELETE apropriadas
-- ----------------------------------------------------------------------------
-- IMPORTANTE: Avaliar requisitos de negócio antes de aplicar

-- Movimentações de turma: permitir SET NULL se turma for deletada
ALTER TABLE student_class_history
DROP CONSTRAINT IF EXISTS student_class_history_class_id_fkey,
ADD CONSTRAINT student_class_history_class_id_fkey
FOREIGN KEY (class_id) REFERENCES classes(id) ON DELETE SET NULL;

ALTER TABLE student_class_history
DROP CONSTRAINT IF EXISTS student_class_history_moved_from_class_id_fkey,
ADD CONSTRAINT student_class_history_moved_from_class_id_fkey
FOREIGN KEY (moved_from_class_id) REFERENCES classes(id) ON DELETE SET NULL;

-- Ocorrências: manter registro histórico mesmo se professor for deletado
ALTER TABLE occurrences
DROP CONSTRAINT IF EXISTS occurrences_teacher_id_fkey,
ADD CONSTRAINT occurrences_teacher_id_fkey
FOREIGN KEY (teacher_id) REFERENCES users(id) ON DELETE SET NULL;

-- Alunos: definir CASCADE se turma for deletada (ou SET NULL se preferir)
-- DESCOMENTE A OPÇÃO DESEJADA:

-- Opção A: SET NULL (aluno fica sem turma)
-- ALTER TABLE students
-- DROP CONSTRAINT IF EXISTS students_class_id_fkey,
-- ADD CONSTRAINT students_class_id_fkey
-- FOREIGN KEY (class_id) REFERENCES classes(id) ON DELETE SET NULL;

-- Opção B: RESTRICT (não permite deletar turma com alunos)
-- ALTER TABLE students
-- DROP CONSTRAINT IF EXISTS students_class_id_fkey,
-- ADD CONSTRAINT students_class_id_fkey
-- FOREIGN KEY (class_id) REFERENCES classes(id) ON DELETE RESTRICT;


-- ============================================================================
-- PARTE 4: LIMPEZA E OTIMIZAÇÃO (PRIORIDADE BAIXA)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 4.1 - Remover índices duplicados/não utilizados
-- ----------------------------------------------------------------------------
-- IMPORTANTE: Avaliar após ter dados em produção
-- Email já tem índice UNIQUE, não precisa de índice adicional

DROP INDEX CONCURRENTLY IF EXISTS idx_users_email;

-- ----------------------------------------------------------------------------
-- 4.2 - Adicionar comentários para documentação
-- ----------------------------------------------------------------------------

COMMENT ON TABLE institutions IS 'Instituições de ensino cadastradas no sistema';
COMMENT ON TABLE users IS 'Usuários do sistema (master, admin, professor)';
COMMENT ON TABLE user_institutions IS 'Relacionamento N:N entre usuários e instituições com role específico';
COMMENT ON TABLE classes IS 'Turmas das instituições por ano letivo';
COMMENT ON TABLE students IS 'Alunos matriculados nas instituições';
COMMENT ON TABLE student_class_history IS 'Histórico de movimentação de alunos entre turmas';
COMMENT ON TABLE occurrence_types IS 'Tipos de ocorrências disciplinares configuráveis por instituição';
COMMENT ON TABLE occurrences IS 'Registros de ocorrências disciplinares dos alunos';
COMMENT ON TABLE access_requests IS 'Solicitações de acesso ao sistema (criação de instituição/usuário)';

COMMENT ON COLUMN users.role IS 'Role global do usuário: master (super admin), admin ou professor';
COMMENT ON COLUMN user_institutions.role IS 'Role do usuário nesta instituição específica: admin ou professor';
COMMENT ON COLUMN students.registration_number IS 'Matrícula do aluno (único por instituição)';
COMMENT ON COLUMN occurrences.occurred_at IS 'Data/hora em que a ocorrência aconteceu (pode ser diferente de created_at)';

-- ----------------------------------------------------------------------------
-- 4.3 - Habilitar extensões úteis (se necessário)
-- ----------------------------------------------------------------------------

-- Para busca full-text em português
-- CREATE EXTENSION IF NOT EXISTS unaccent;
-- CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- Para auditoria de mudanças
-- CREATE EXTENSION IF NOT EXISTS pgaudit;

-- Para jobs agendados (relatórios, limpeza)
-- CREATE EXTENSION IF NOT EXISTS pg_cron;


-- ============================================================================
-- VERIFICAÇÕES PÓS-APLICAÇÃO
-- ============================================================================

-- Verificar políticas RLS em student_class_history
SELECT schemaname, tablename, policyname, cmd
FROM pg_policies
WHERE tablename = 'student_class_history'
ORDER BY cmd;

-- Verificar índices criados
SELECT schemaname, tablename, indexname
FROM pg_indexes
WHERE schemaname = 'public'
ORDER BY tablename, indexname;

-- Verificar constraints de foreign keys
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

-- Verificar tabelas sem políticas RLS
SELECT schemaname, tablename, rowsecurity
FROM pg_tables
WHERE schemaname = 'public'
  AND rowsecurity = true
  AND tablename NOT IN (
    SELECT DISTINCT tablename FROM pg_policies WHERE schemaname = 'public'
  );

-- ============================================================================
-- FIM DOS SCRIPTS
-- ============================================================================
