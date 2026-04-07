/*
 * Converted from: oracle-sql/05_package_conversion.sql
 * Description:     Oracle package pkg_employee_mgmt (spec + body) converted to
 *                  T-SQL schema with individual stored procedures and functions.
 *
 * MIGRATION WARNING: Oracle packages provide per-session state, encapsulation,
 *   and an initialization block. T-SQL has no direct equivalent. This conversion
 *   uses a schema to namespace the package members. Package-level variables and
 *   the initialization block have been removed — see notes in each procedure.
 * MIGRATION WARNING: Oracle package-spec types (t_employee_rec, t_employee_tab,
 *   t_emp_cursor) have no direct T-SQL equivalent. If other Oracle code references
 *   these types, those callers must also be updated.
 * MIGRATION NOTE: Oracle treats empty string ('') as NULL. SQL Server does not.
 *   Review all NULL/empty-string checks if migrated data may contain empty strings.
 */

SET ANSI_NULLS ON;
GO

SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================
-- Create schema to represent the Oracle package
-- ============================================================
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = N'pkg_employee_mgmt')
    EXEC(N'CREATE SCHEMA [pkg_employee_mgmt]');
GO

-- ============================================================
-- Package Constants (defined inline in each procedure/function)
-- ============================================================
-- MIGRATION WARNING: Oracle package constants (gc_max_salary = 500000,
--   gc_min_salary = 30000, gc_default_dept = 10) were accessible to all
--   package members. In T-SQL these are declared as local variables in
--   each procedure/function that needs them. If centralized management
--   is required, consider a configuration table or scalar functions.

-- ============================================================
-- MIGRATION WARNING: Package-level variables removed
-- ============================================================
-- Oracle package variables g_last_hire_id and g_operation_log provided
-- per-session in-memory state. T-SQL has no equivalent. The log_operation
-- helper now only emits PRINT messages. If persistent logging is needed,
-- insert into a dedicated log table instead.

-- ============================================================
-- MIGRATION WARNING: Package initialization block removed
-- ============================================================
-- Oracle:  BEGIN g_last_hire_id := NULL;
--          g_operation_log := 'Package initialized at ' || TO_CHAR(SYSDATE, ...);
--          DBMS_OUTPUT.PUT_LINE(g_operation_log); END;
-- T-SQL has no session-level initialization block. Any required setup
-- must be performed explicitly by the application before calling these
-- procedures.

-- ============================================================
-- Private helper: log_operation
-- MIGRATION NOTE: Was a private package procedure. In T-SQL all schema
--   members are public. Prefix with underscore to signal internal use.
-- MIGRATION NOTE: Oracle version appended to g_operation_log (package
--   variable). T-SQL version only emits a PRINT message.
-- ============================================================
CREATE OR ALTER PROCEDURE [pkg_employee_mgmt].[_log_operation]
    @p_message NVARCHAR(4000)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @log_entry NVARCHAR(4000) = CONCAT(FORMAT(GETDATE(), N'yyyy-MM-dd HH:mm:ss'), N' - ', @p_message);
    PRINT @log_entry;
END;
GO

-- ============================================================
-- Private helper: validate_salary
-- MIGRATION NOTE: Was a private package function returning BOOLEAN.
--   Converted to a scalar function returning BIT (1 = valid, 0 = invalid).
-- ============================================================
CREATE OR ALTER FUNCTION [pkg_employee_mgmt].[validate_salary]
(
    @p_salary DECIMAL(10,2)
)
RETURNS BIT
AS
BEGIN
    DECLARE @gc_min_salary DECIMAL(10,2) = 30000;
    DECLARE @gc_max_salary DECIMAL(10,2) = 500000;

    IF @p_salary >= @gc_min_salary AND @p_salary <= @gc_max_salary
        RETURN 1;

    RETURN 0;
END;
GO

-- ============================================================
-- hire_employee
-- ============================================================
CREATE OR ALTER PROCEDURE [pkg_employee_mgmt].[hire_employee]
    @p_first_name   NVARCHAR(200),
    @p_last_name    NVARCHAR(200),
    @p_email        NVARCHAR(200),
    @p_salary       DECIMAL(10,2)   = 30000,       -- MIGRATION NOTE: default was gc_min_salary
    @p_dept_id      INT             = 10,           -- MIGRATION NOTE: default was gc_default_dept
    @p_employee_id  BIGINT          OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    -- Package constants (local copies)
    DECLARE @gc_min_salary DECIMAL(10,2) = 30000;
    DECLARE @gc_max_salary DECIMAL(10,2) = 500000;

    DECLARE @v_emp_id     BIGINT;
    DECLARE @v_exists     INT;
    DECLARE @own_tran     BIT = 0;
    DECLARE @err_msg      NVARCHAR(2048);

    BEGIN TRY
        -- Validate salary
        IF [pkg_employee_mgmt].[validate_salary](@p_salary) = 0
        BEGIN
            SET @err_msg = CONCAT(N'Salary ', @p_salary, N' out of range [', @gc_min_salary, N', ', @gc_max_salary, N']');
            THROW 50010, @err_msg, 1;
        END;

        -- MIGRATION NOTE: Oracle treats '' as NULL; in T-SQL we check both
        IF @p_first_name IS NULL OR @p_first_name = N'' OR @p_last_name IS NULL OR @p_last_name = N''
        BEGIN
            THROW 50011, N'First and last name are required', 1;
        END;

        -- Check for duplicate email
        SELECT @v_exists = COUNT(*)
        FROM [dbo].[employees]
        WHERE email = @p_email;

        IF @v_exists > 0
        BEGIN
            SET @err_msg = CONCAT(N'Email already exists: ', @p_email);
            THROW 50012, @err_msg, 1;
        END;

        -- MIGRATION NOTE: Transaction is only started if no outer transaction exists.
        -- Oracle version used unconditional COMMIT; in T-SQL, callers often manage transactions.
        IF @@TRANCOUNT = 0
        BEGIN
            BEGIN TRANSACTION;
            SET @own_tran = 1;
        END;

        -- Insert the employee
        -- MIGRATION NOTE: Oracle RETURNING INTO replaced with OUTPUT clause
        DECLARE @inserted TABLE (id BIGINT);

        INSERT INTO [dbo].[employees] (
            employee_id, first_name, last_name, email,
            hire_date, salary, department_id, is_active, created_at
        )
        OUTPUT inserted.employee_id INTO @inserted
        VALUES (
            NEXT VALUE FOR [dbo].[emp_seq],
            @p_first_name, @p_last_name, @p_email,
            GETDATE(), @p_salary, @p_dept_id, 1, SYSDATETIMEOFFSET()
        );

        SELECT @v_emp_id = id FROM @inserted;
        SET @p_employee_id = @v_emp_id;

        -- MIGRATION NOTE: g_last_hire_id package variable removed; value is returned via OUTPUT parameter
        DECLARE @hire_msg NVARCHAR(4000) = CONCAT(N'Hired: ', @p_first_name, N' ', @p_last_name, N' (ID: ', @v_emp_id, N')');
        EXEC [pkg_employee_mgmt].[_log_operation] @p_message = @hire_msg;

        IF @own_tran = 1
            COMMIT TRANSACTION;

    END TRY
    BEGIN CATCH
        IF @own_tran = 1 AND XACT_STATE() <> 0
            ROLLBACK TRANSACTION;

        -- MIGRATION NOTE: Oracle DUP_VAL_ON_INDEX maps to SQL Server errors 2627 (unique constraint) and 2601 (unique index)
        IF ERROR_NUMBER() IN (2627, 2601)
        BEGIN
            THROW 50012, N'Duplicate constraint violation during hire', 1;
        END;

        DECLARE @catch_msg NVARCHAR(4000) = CONCAT(N'Error in hire_employee: ', ERROR_MESSAGE());
        EXEC [pkg_employee_mgmt].[_log_operation] @p_message = @catch_msg;
        THROW;
    END CATCH;
END;
GO

-- ============================================================
-- terminate_employee
-- ============================================================
CREATE OR ALTER PROCEDURE [pkg_employee_mgmt].[terminate_employee]
    @p_employee_id  BIGINT,
    @p_reason       NVARCHAR(4000)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @v_emp_name   NVARCHAR(200);
    DECLARE @own_tran     BIT = 0;
    DECLARE @err_msg      NVARCHAR(2048);

    BEGIN TRY
        -- Get employee info
        -- MIGRATION NOTE: Oracle SELECT INTO raises NO_DATA_FOUND / TOO_MANY_ROWS.
        -- T-SQL does neither. employee_id is expected to be a PK (unique), so >1 row is not possible.
        -- We check @@ROWCOUNT = 0 for the no-data case.
        SELECT @v_emp_name = CONCAT(first_name, N' ', last_name)
        FROM [dbo].[employees]
        WHERE employee_id = @p_employee_id;

        IF @@ROWCOUNT = 0
        BEGIN
            SET @err_msg = CONCAT(N'Employee not found: ', @p_employee_id);
            THROW 50020, @err_msg, 1;
        END;

        IF @@TRANCOUNT = 0
        BEGIN
            BEGIN TRANSACTION;
            SET @own_tran = 1;
        END;

        -- Soft delete
        UPDATE [dbo].[employees]
        SET is_active = 0,
            updated_at = SYSDATETIMEOFFSET()
        WHERE employee_id = @p_employee_id;

        -- Archive record
        INSERT INTO [dbo].[employee_archive] (employee_id, terminated_date, reason)
        VALUES (@p_employee_id, GETDATE(), @p_reason);

        DECLARE @term_msg NVARCHAR(4000) = CONCAT(N'Terminated: ', @v_emp_name, N' - Reason: ', @p_reason);
        EXEC [pkg_employee_mgmt].[_log_operation] @p_message = @term_msg;

        IF @own_tran = 1
            COMMIT TRANSACTION;

    END TRY
    BEGIN CATCH
        IF @own_tran = 1 AND XACT_STATE() <> 0
            ROLLBACK TRANSACTION;

        DECLARE @catch_msg NVARCHAR(4000) = CONCAT(N'Error in terminate_employee: ', ERROR_MESSAGE());
        EXEC [pkg_employee_mgmt].[_log_operation] @p_message = @catch_msg;
        THROW;
    END CATCH;
END;
GO

-- ============================================================
-- transfer_employee
-- ============================================================
CREATE OR ALTER PROCEDURE [pkg_employee_mgmt].[transfer_employee]
    @p_employee_id    BIGINT,
    @p_new_dept_id    INT,
    @p_salary_adjust  DECIMAL(10,2)  = 0
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @v_old_dept    INT;
    DECLARE @v_new_salary  DECIMAL(10,2);
    DECLARE @own_tran      BIT = 0;
    DECLARE @err_msg       NVARCHAR(2048);

    BEGIN TRY
        -- MIGRATION NOTE: Oracle SELECT INTO raises NO_DATA_FOUND. Using @@ROWCOUNT check.
        -- employee_id is expected to be a PK (unique), so TOO_MANY_ROWS is not possible.
        SELECT @v_old_dept   = department_id,
               @v_new_salary = salary + @p_salary_adjust
        FROM [dbo].[employees]
        WHERE employee_id = @p_employee_id;

        IF @@ROWCOUNT = 0
        BEGIN
            SET @err_msg = CONCAT(N'Employee not found: ', @p_employee_id);
            THROW 50031, @err_msg, 1;
        END;

        IF [pkg_employee_mgmt].[validate_salary](@v_new_salary) = 0
        BEGIN
            THROW 50030, N'Adjusted salary out of valid range', 1;
        END;

        IF @@TRANCOUNT = 0
        BEGIN
            BEGIN TRANSACTION;
            SET @own_tran = 1;
        END;

        UPDATE [dbo].[employees]
        SET department_id = @p_new_dept_id,
            salary = @v_new_salary,
            updated_at = SYSDATETIMEOFFSET()
        WHERE employee_id = @p_employee_id;

        INSERT INTO [dbo].[transfer_log] (employee_id, from_dept, to_dept, transfer_date, salary_change)
        VALUES (@p_employee_id, @v_old_dept, @p_new_dept_id, GETDATE(), @p_salary_adjust);

        DECLARE @xfer_msg NVARCHAR(4000) = CONCAT(N'Transferred emp ', @p_employee_id,
            N' from dept ', @v_old_dept, N' to dept ', @p_new_dept_id);
        EXEC [pkg_employee_mgmt].[_log_operation] @p_message = @xfer_msg;

        IF @own_tran = 1
            COMMIT TRANSACTION;

    END TRY
    BEGIN CATCH
        IF @own_tran = 1 AND XACT_STATE() <> 0
            ROLLBACK TRANSACTION;

        THROW;
    END CATCH;
END;
GO

-- ============================================================
-- get_employee_count
-- ============================================================
CREATE OR ALTER FUNCTION [pkg_employee_mgmt].[get_employee_count]
(
    @p_department_id INT = NULL
)
RETURNS INT
AS
BEGIN
    DECLARE @v_count INT;

    IF @p_department_id IS NULL
        SELECT @v_count = COUNT(*) FROM [dbo].[employees] WHERE is_active = 1;
    ELSE
        SELECT @v_count = COUNT(*)
        FROM [dbo].[employees]
        WHERE department_id = @p_department_id AND is_active = 1;

    RETURN @v_count;
END;
GO

-- ============================================================
-- get_department_employees
-- MIGRATION WARNING: Oracle version was a function returning REF CURSOR
--   (t_emp_cursor). T-SQL functions cannot return result sets, so this
--   is converted to a stored procedure that returns its result set
--   directly. All callers must change from:
--     v_cursor := pkg_employee_mgmt.get_department_employees(10);
--   to:
--     EXEC [pkg_employee_mgmt].[get_department_employees] @p_department_id = 10;
-- ============================================================
CREATE OR ALTER PROCEDURE [pkg_employee_mgmt].[get_department_employees]
    @p_department_id INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT e.employee_id,
           CONCAT(e.first_name, N' ', e.last_name) AS full_name,
           e.salary,
           d.department_name
    FROM [dbo].[employees] e
    INNER JOIN [dbo].[departments] d ON e.department_id = d.department_id
    WHERE e.department_id = @p_department_id
      AND e.is_active = 1
    ORDER BY e.last_name;
END;
GO

-- ============================================================
-- calculate_annual_cost
-- ============================================================
CREATE OR ALTER FUNCTION [pkg_employee_mgmt].[calculate_annual_cost]
(
    @p_department_id INT
)
RETURNS DECIMAL(18,2)
AS
BEGIN
    DECLARE @v_total DECIMAL(18,2) = 0;

    -- MIGRATION NOTE: NVL → COALESCE
    SELECT @v_total = COALESCE(SUM(salary * 12 + COALESCE(salary * commission_pct * 12, 0)), 0)
    FROM [dbo].[employees]
    WHERE department_id = @p_department_id
      AND is_active = 1;

    RETURN @v_total;
END;
GO
