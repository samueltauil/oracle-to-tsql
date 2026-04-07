-- =====================================================================
-- File:        04_tricky_patterns.sql
-- Source:      oracle-sql/04_tricky_patterns.sql
-- Description: Converted tricky Oracle-specific patterns to T-SQL
--              including hierarchical queries, old-style joins,
--              empty-string-as-NULL semantics, DECODE NULL handling,
--              ROWNUM patterns, RETURNING INTO, dynamic SQL, and
--              BULK COLLECT/FORALL.
-- =====================================================================

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================
-- 1. CONNECT BY hierarchical query with LEVEL and SYS_CONNECT_BY_PATH
-- MIGRATION NOTE: Oracle CONNECT BY converted to recursive CTE.
--   - LEVEL            → depth column incremented in recursive member
--   - SYS_CONNECT_BY_PATH → management_chain built via CONCAT
--   - CONNECT_BY_ISLEAF   → NOT EXISTS subquery against children
--   - CONNECT_BY_ROOT     → top_manager carried from anchor
--   - ORDER SIBLINGS BY   → sort_path built from zero-padded sibling
--                           ordinals at each level
-- MIGRATION NOTE: Oracle sorts NULLs last by default; SQL Server
--   sorts NULLs first. Ordering may differ for NULL last_name values.
-- ============================================================

-- Pre-compute sibling ordinals for ORDER SIBLINGS BY emulation
;WITH SiblingOrd AS (
    SELECT
        employee_id,
        first_name,
        last_name,
        manager_id,
        RIGHT(REPLICATE('0', 10) + CAST(
            ROW_NUMBER() OVER (PARTITION BY manager_id ORDER BY last_name, employee_id)
        AS NVARCHAR(10)), 10) AS sibling_ordinal
    FROM [dbo].[employees]
),
EmployeeCTE AS (
    -- Anchor: root employees (no manager)
    SELECT
        s.employee_id,
        CONCAT(s.first_name, N' ', s.last_name)    AS employee_name,
        s.manager_id,
        1                                           AS depth,
        CAST(CONCAT(N' > ', s.last_name) AS NVARCHAR(4000)) AS management_chain,
        CAST(s.last_name AS NVARCHAR(4000))         AS indented_name,
        s.last_name                                 AS top_manager,
        CAST(s.sibling_ordinal AS NVARCHAR(4000))   AS sort_path
    FROM SiblingOrd s
    WHERE s.manager_id IS NULL

    UNION ALL

    -- Recursive: children joined to their parents
    SELECT
        s.employee_id,
        CONCAT(s.first_name, N' ', s.last_name)    AS employee_name,
        s.manager_id,
        c.depth + 1                                 AS depth,
        CAST(CONCAT(c.management_chain, N' > ', s.last_name) AS NVARCHAR(4000)) AS management_chain,
        CAST(CONCAT(REPLICATE(N' ', c.depth * 4), s.last_name) AS NVARCHAR(4000)) AS indented_name,
        c.top_manager,
        CAST(CONCAT(c.sort_path, N'/', s.sibling_ordinal) AS NVARCHAR(4000)) AS sort_path
    FROM SiblingOrd s
    INNER JOIN EmployeeCTE c ON s.manager_id = c.employee_id
)
SELECT
    e.employee_id,
    e.employee_name,
    e.manager_id,
    e.depth,
    e.management_chain,
    e.indented_name,
    CASE WHEN NOT EXISTS (
        SELECT 1 FROM [dbo].[employees] child
        WHERE child.manager_id = e.employee_id
    ) THEN 1 ELSE 0 END                            AS is_leaf,
    e.top_manager
FROM EmployeeCTE e
ORDER BY e.sort_path
OPTION (MAXRECURSION 100);
-- MIGRATION NOTE: MAXRECURSION set to 100 (SQL Server default).
--   Increase or set to 0 for deeper hierarchies, but add cycle detection if data may contain circular references.
GO

-- ============================================================
-- 2. Old-style (+) outer join syntax
-- MIGRATION NOTE: Oracle (+) syntax converted to ANSI JOIN syntax.
-- ============================================================

-- Left outer join via (+)
SELECT e.employee_id, e.last_name, d.department_name
FROM [dbo].[employees] e
LEFT JOIN [dbo].[departments] d ON e.department_id = d.department_id;
GO

-- Right outer join via (+)
SELECT e.employee_id, e.last_name, d.department_name
FROM [dbo].[employees] e
RIGHT JOIN [dbo].[departments] d ON e.department_id = d.department_id;
GO

-- Multiple (+) conditions
-- MIGRATION NOTE: The filter l.country_id(+) = 'US' is placed in the ON clause
--   of the LEFT JOIN to locations. Placing it in WHERE would convert the outer
--   join to an inner join, silently changing semantics.
SELECT e.employee_id, e.last_name, d.department_name, l.city
FROM [dbo].[employees] e
LEFT JOIN [dbo].[departments] d ON e.department_id = d.department_id
LEFT JOIN [dbo].[locations] l ON d.location_id = l.location_id
    AND l.country_id = N'US';
GO

-- ============================================================
-- 3. Empty string = NULL (Oracle's most dangerous semantic difference)
-- MIGRATION WARNING: Oracle treats '' as NULL. SQL Server does NOT.
--   Every string comparison, IS NULL check, NVL/COALESCE, INSERT, and
--   concatenation involving potentially empty strings must be audited.
-- ============================================================

-- MIGRATION NOTE: In Oracle '' IS NULL evaluates to TRUE.
-- These queries behave DIFFERENTLY in SQL Server.

-- This finds employees with no name in Oracle (NULL and '')
-- MIGRATION NOTE: Added OR first_name = N'' to preserve Oracle semantics
--   where '' IS NULL is TRUE.
SELECT * FROM [dbo].[employees] WHERE first_name IS NULL OR first_name = N'';
GO

-- This inserts a NULL in Oracle ('' becomes NULL)
-- MIGRATION NOTE: Changed '' to NULL to preserve Oracle semantics.
INSERT INTO [dbo].[employees] (employee_id, first_name, last_name, hire_date, email)
VALUES (999, NULL, N'TestUser', GETDATE(), N'test@example.com');
GO

-- NVL with empty string — in Oracle NVL('', 'default') returns 'default'
-- MIGRATION NOTE: NULLIF(first_name, N'') converts empty string to NULL before
--   COALESCE, preserving Oracle's behavior where '' is treated as NULL.
SELECT COALESCE(NULLIF(first_name, N''), N'No Name') AS display_name
FROM [dbo].[employees];
GO

-- String comparison with empty string
-- MIGRATION NOTE: In Oracle, WHERE first_name = '' is always false ('' IS NULL,
--   and NULL = NULL is unknown). Replaced with WHERE 1 = 0 to preserve
--   Oracle's behavior of never returning rows.
SELECT * FROM [dbo].[employees] WHERE 1 = 0;
GO

-- MIGRATION NOTE: Added AND first_name <> N'' to exclude empty strings,
--   preserving Oracle semantics where '' IS NULL and IS NOT NULL excludes ''.
SELECT * FROM [dbo].[employees] WHERE first_name IS NOT NULL AND first_name <> N'';
GO

-- Concatenation with empty/null string
-- MIGRATION NOTE: Oracle's || ignores NULL operands; SQL Server + propagates NULL.
--   CONCAT() treats NULL as empty string, which is closest to Oracle's behavior.
--   The original '' operand was meaningless in Oracle (treated as NULL and ignored).
SELECT CONCAT(first_name, last_name) FROM [dbo].[employees];
GO

-- ============================================================
-- 4. DECODE with NULL comparisons
-- MIGRATION NOTE: Oracle DECODE treats NULL = NULL as TRUE.
--   T-SQL CASE x WHEN NULL does NOT match NULLs.
--   All NULL comparisons converted to CASE WHEN x IS NULL.
-- ============================================================

SELECT
    employee_id,
    CASE WHEN manager_id IS NULL THEN N'CEO'
         ELSE N'Has Manager'
    END                                                         AS mgr_status,
    CASE WHEN commission_pct IS NULL THEN 0
         ELSE commission_pct * salary
    END                                                         AS commission,
    -- MIGRATION NOTE: Uses NULLIF to treat empty first_name as NULL,
    --   preserving Oracle's '' = NULL semantics within DECODE.
    CASE WHEN NULLIF(first_name, N'') IS NULL THEN last_name
         ELSE CONCAT(first_name, N' ', last_name)
    END                                                         AS full_name
FROM [dbo].[employees];
GO

-- ============================================================
-- 5. ROWNUM with ORDER BY (order of evaluation trap)
-- ============================================================

-- MIGRATION WARNING: Oracle assigns ROWNUM before ORDER BY, so the original
--   query does NOT return the top 5 highest-paid employees. It picks 5
--   arbitrary rows, then orders them. This conversion preserves that
--   (buggy) Oracle behavior. The next query shows the correct pattern.
SELECT employee_id, last_name, salary
FROM (
    SELECT TOP 5 employee_id, last_name, salary
    FROM [dbo].[employees]
) t
ORDER BY salary DESC;
GO

-- Correct Oracle pattern (subquery) — returns top 5 highest-paid
SELECT TOP 5 employee_id, last_name, salary
FROM [dbo].[employees]
ORDER BY salary DESC;
GO

-- Pagination pattern
-- MIGRATION NOTE: Oracle ROWNUM pagination converted to OFFSET...FETCH.
--   Original: rows 21–30 from salary-descending order.
SELECT employee_id, last_name, salary
FROM [dbo].[employees]
ORDER BY salary DESC
OFFSET 20 ROWS FETCH NEXT 10 ROWS ONLY;
GO

-- ============================================================
-- 6. RETURNING INTO clause
-- MIGRATION NOTE: Oracle RETURNING INTO converted to OUTPUT clause
--   with a table variable. Sequence .NEXTVAL → NEXT VALUE FOR.
-- ============================================================

DECLARE @v_new_id INT;
DECLARE @inserted TABLE (employee_id INT);

INSERT INTO [dbo].[employees] (employee_id, first_name, last_name, hire_date, email, salary)
OUTPUT inserted.employee_id INTO @inserted
VALUES (NEXT VALUE FOR [dbo].[emp_seq], N'John', N'Doe', GETDATE(), N'john.doe@example.com', 75000);

SELECT @v_new_id = employee_id FROM @inserted;

PRINT CONCAT(N'New employee ID: ', @v_new_id);
GO

-- ============================================================
-- 7. EXECUTE IMMEDIATE (dynamic SQL)
-- MIGRATION NOTE: Oracle EXECUTE IMMEDIATE converted to sp_executesql.
--   - Table name uses QUOTENAME() for identifier safety.
--   - SYSDATE - :days → DATEADD(DAY, -@p_days_old, GETDATE())
--   - Bind variables mapped to sp_executesql parameters.
-- MIGRATION WARNING: Dynamic SQL identifier safety — p_table_name is
--   concatenated into SQL. QUOTENAME() prevents injection but does not
--   validate authorization or table shape. Consider adding a whitelist
--   or metadata validation in production.
-- ============================================================

CREATE OR ALTER PROCEDURE [dbo].[archive_old_records]
    @p_table_name NVARCHAR(128),
    @p_days_old   INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @v_sql    NVARCHAR(4000);
    DECLARE @v_count  INT;
    DECLARE @v_safe_table   NVARCHAR(256) = QUOTENAME(@p_table_name);
    DECLARE @v_safe_archive NVARCHAR(256) = QUOTENAME(@p_table_name + N'_archive');
    DECLARE @v_tran_started BIT = 0;

    BEGIN TRY
        -- Validate that source and archive tables exist
        IF OBJECT_ID(@p_table_name, 'U') IS NULL
        BEGIN
            ;THROW 50001, N'Source table does not exist.', 1;
        END;

        IF OBJECT_ID(@p_table_name + N'_archive', 'U') IS NULL
        BEGIN
            ;THROW 50002, N'Archive table does not exist.', 1;
        END;

        -- Dynamic SQL with parameterized date comparison
        SET @v_sql = N'SELECT @cnt = COUNT(*) FROM ' + @v_safe_table
                   + N' WHERE created_at < DATEADD(DAY, -@days_old, GETDATE())';
        EXEC sp_executesql @v_sql,
            N'@days_old INT, @cnt INT OUTPUT',
            @days_old = @p_days_old,
            @cnt = @v_count OUTPUT;

        PRINT CONCAT(N'Records to archive: ', @v_count);

        -- MIGRATION NOTE: Transaction ownership pattern — only start/commit
        --   a transaction if we are not already inside a caller's transaction.
        IF @@TRANCOUNT = 0
        BEGIN
            BEGIN TRANSACTION;
            SET @v_tran_started = 1;
        END;

        -- Dynamic DML — archive
        SET @v_sql = N'INSERT INTO ' + @v_safe_archive
                   + N' SELECT * FROM ' + @v_safe_table
                   + N' WHERE created_at < DATEADD(DAY, -@days_old, GETDATE())';
        EXEC sp_executesql @v_sql,
            N'@days_old INT',
            @days_old = @p_days_old;

        -- Dynamic DML — delete
        SET @v_sql = N'DELETE FROM ' + @v_safe_table
                   + N' WHERE created_at < DATEADD(DAY, -@days_old, GETDATE())';
        EXEC sp_executesql @v_sql,
            N'@days_old INT',
            @days_old = @p_days_old;

        IF @v_tran_started = 1
            COMMIT TRANSACTION;

    END TRY
    BEGIN CATCH
        IF @v_tran_started = 1 AND @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO

-- ============================================================
-- 8. BULK COLLECT and FORALL
-- MIGRATION NOTE: Oracle BULK COLLECT + FORALL replaced with a single
--   set-based UPDATE. This is idiomatic T-SQL and far more efficient
--   than row-by-row cursor processing.
-- MIGRATION NOTE: COMMIT removed — let the caller manage transaction
--   boundaries. SQL%ROWCOUNT → @@ROWCOUNT.
-- ============================================================

UPDATE [dbo].[employees]
SET salary = salary * 1.1
WHERE department_id = 10;

PRINT CONCAT(N'Updated ', CAST(@@ROWCOUNT AS NVARCHAR(10)), N' employees');
GO
