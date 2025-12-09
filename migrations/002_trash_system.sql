-- ============================================================================
-- SISTEMA DE LIXEIRA - Gestão Escolar
-- ============================================================================
-- Data: 2025-10-27
-- Descrição: Implementação de sistema de lixeira (soft delete avançado)
-- ============================================================================

-- ============================================================================
-- PARTE 1: ADICIONAR CAMPOS DE LIXEIRA
-- ============================================================================

-- Adicionar campos na tabela users (professores)
ALTER TABLE users
ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMP NULL,
ADD COLUMN IF NOT EXISTS deleted_by UUID REFERENCES users(id) NULL;

-- Adicionar campos na tabela students (alunos)
ALTER TABLE students
ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMP NULL,
ADD COLUMN IF NOT EXISTS deleted_by UUID REFERENCES users(id) NULL;

-- Comentários explicativos
COMMENT ON COLUMN users.deleted_at IS 'Data e hora em que o usuário foi movido para a lixeira. NULL = não está na lixeira';
COMMENT ON COLUMN users.deleted_by IS 'ID do usuário (admin/master) que moveu este registro para a lixeira';
COMMENT ON COLUMN students.deleted_at IS 'Data e hora em que o aluno foi movido para a lixeira. NULL = não está na lixeira';
COMMENT ON COLUMN students.deleted_by IS 'ID do usuário (admin/master) que moveu este registro para a lixeira';

-- ============================================================================
-- PARTE 2: CRIAR ÍNDICES PARA PERFORMANCE
-- ============================================================================

-- Índices para acelerar queries que filtram por deleted_at
CREATE INDEX IF NOT EXISTS idx_users_deleted_at ON users(deleted_at);
CREATE INDEX IF NOT EXISTS idx_students_deleted_at ON students(deleted_at);

-- Índice composto para queries que filtram por instituição + deleted_at
CREATE INDEX IF NOT EXISTS idx_users_institution_deleted
ON users(institution_id, deleted_at)
WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_students_institution_deleted
ON students(institution_id, deleted_at)
WHERE deleted_at IS NULL;

-- ============================================================================
-- PARTE 3: ATUALIZAR POLÍTICAS RLS (Row Level Security)
-- ============================================================================

-- Nota: As políticas RLS existentes já funcionarão com o sistema de lixeira
-- pois o campo deleted_at é apenas um filtro adicional no nível da aplicação.
-- Mas vamos criar políticas específicas para garantir segurança.

-- Política: Apenas Master pode deletar permanentemente
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
  -- Apenas Master pode deletar permanentemente
  EXISTS (
    SELECT 1 FROM user_institutions ui
    WHERE ui.user_id = auth.uid()
    AND ui.role = 'master'
  )
  OR
  -- Ou Admin da mesma instituição pode deletar (se não tiver dados relacionados - verificar no código)
  EXISTS (
    SELECT 1 FROM user_institutions ui
    WHERE ui.user_id = auth.uid()
    AND ui.institution_id = students.institution_id
    AND ui.role = 'admin'
  )
);

-- ============================================================================
-- PARTE 4: FUNÇÃO PARA MOVER PARA LIXEIRA
-- ============================================================================

-- Função helper para mover usuário para lixeira
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
    is_active = false  -- Garantir que também fica inativo
  WHERE id = p_user_id;

  RETURN FOUND;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Função helper para restaurar usuário da lixeira
CREATE OR REPLACE FUNCTION restore_user_from_trash(
  p_user_id UUID
)
RETURNS BOOLEAN AS $$
BEGIN
  UPDATE users
  SET
    deleted_at = NULL,
    deleted_by = NULL,
    is_active = false  -- Volta como INATIVO (admin precisa ativar manualmente)
  WHERE id = p_user_id;

  RETURN FOUND;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Função helper para mover aluno para lixeira
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
    is_active = false  -- Garantir que também fica inativo
  WHERE id = p_student_id;

  RETURN FOUND;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Função helper para restaurar aluno da lixeira
CREATE OR REPLACE FUNCTION restore_student_from_trash(
  p_student_id UUID
)
RETURNS BOOLEAN AS $$
BEGIN
  UPDATE students
  SET
    deleted_at = NULL,
    deleted_by = NULL,
    is_active = false  -- Volta como INATIVO (admin precisa ativar manualmente)
  WHERE id = p_student_id;

  RETURN FOUND;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- PARTE 5: VIEW PARA FACILITAR QUERIES
-- ============================================================================

-- View para listar apenas usuários ativos (não na lixeira)
CREATE OR REPLACE VIEW active_users AS
SELECT * FROM users
WHERE deleted_at IS NULL;

-- View para listar apenas usuários na lixeira
CREATE OR REPLACE VIEW trashed_users AS
SELECT * FROM users
WHERE deleted_at IS NOT NULL;

-- View para listar apenas alunos ativos (não na lixeira)
CREATE OR REPLACE VIEW active_students AS
SELECT * FROM students
WHERE deleted_at IS NULL;

-- View para listar apenas alunos na lixeira
CREATE OR REPLACE VIEW trashed_students AS
SELECT * FROM students
WHERE deleted_at IS NOT NULL;

-- ============================================================================
-- PARTE 6: LIMPEZA AUTOMÁTICA (OPCIONAL)
-- ============================================================================

-- Função para deletar permanentemente registros antigos da lixeira
-- (Executar manualmente ou via cron job)
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
  -- Deletar usuários na lixeira há mais de X dias
  WITH deleted AS (
    DELETE FROM users
    WHERE deleted_at < NOW() - INTERVAL '1 day' * p_days_old
    AND deleted_at IS NOT NULL
    RETURNING *
  )
  SELECT COUNT(*) INTO v_users_count FROM deleted;

  -- Deletar alunos na lixeira há mais de X dias
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
-- COMANDOS ÚTEIS PARA ADMINISTRAÇÃO
-- ============================================================================

-- Ver quantidade de registros na lixeira
-- SELECT COUNT(*) FROM users WHERE deleted_at IS NOT NULL;
-- SELECT COUNT(*) FROM students WHERE deleted_at IS NOT NULL;

-- Ver registros na lixeira com informações de quem deletou
-- SELECT u.*, d.name as deleted_by_name
-- FROM users u
-- LEFT JOIN users d ON u.deleted_by = d.id
-- WHERE u.deleted_at IS NOT NULL;

-- Limpar lixeira (deletar registros com mais de 90 dias)
-- SELECT * FROM cleanup_old_trash(90);

-- ============================================================================
-- FIM DO SCRIPT
-- ============================================================================
