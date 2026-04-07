-- =============================================
-- Converted from: oracle-sql/03_plsql_procedure.sql
-- Test file: PL/SQL procedure with cursors, exception handling, variables
-- Covers %TYPE, %ROWTYPE, FOR LOOP cursors, RAISE_APPLICATION_ERROR
-- =============================================

SET ANSI_NULLS ON;
GO

SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE [dbo].[process_department_bonuses]
    @p_department_id    INT,
    @p_bonus_pct        DECIMAL(5,2),
    @p_total_paid       DECIMAL(18,2) OUTPUT,
    @p_emp_count        INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    -- MIGRATION WARNING: Oracle COMMIT/ROLLBACK inside the procedure affects the session
    -- transaction directly. In SQL Server, if this procedure is called within an existing
    -- transaction, ROLLBACK will roll back the entire transaction stack. Review callers.

    DECLARE @v_emp_name     NVARCHAR(100);       -- MIGRATION NOTE: was employees.last_name%TYPE
    DECLARE @v_salary       DECIMAL(10,2);       -- MIGRATION NOTE: was employees.salary%TYPE
    DECLARE @v_bonus        DECIMAL(10,2);
    DECLARE @v_max_bonus    DECIMAL(18,0) = 50000; -- MIGRATION NOTE: Oracle CONSTANT; T-SQL has no procedure-level constants
    DECLARE @v_dept_name    NVARCHAR(100);
    DECLARE @v_processed    INT = 0;
    DECLARE @v_total        DECIMAL(18,2) = 0;
    DECLARE @v_error_msg    NVARCHAR(500);

    -- Cursor fetch variables
    -- MIGRATION NOTE: Oracle cursor FOR LOOP auto-declares rec; T-SQL requires explicit variables
    DECLARE @v_employee_id      BIGINT;
    DECLARE @v_first_name       NVARCHAR(50);
    DECLARE @v_last_name        NVARCHAR(100);
    DECLARE @v_cur_salary       DECIMAL(10,2);
    DECLARE @v_commission_pct   DECIMAL(4,2);

    -- Explicit cursor
    -- MIGRATION NOTE: Using STATIC cursor to snapshot results before UPDATE modifies salary
    DECLARE c_employees CURSOR LOCAL STATIC READ_ONLY FORWARD_ONLY FOR
        SELECT employee_id, first_name, last_name, salary, commission_pct
        FROM [dbo].[employees]
        WHERE department_id = @p_department_id
          AND is_active = 1
        ORDER BY salary DESC;

    BEGIN TRY
        -- Validate inputs
        -- MIGRATION NOTE: Oracle source does not check for NULL p_bonus_pct; behavior preserved
        IF @p_department_id IS NULL
        BEGIN
            THROW 50001, N'Department ID cannot be null', 1;
        END

        IF @p_bonus_pct <= 0 OR @p_bonus_pct > 100
        BEGIN
            THROW 50002, N'Bonus percentage must be between 0 and 100', 1;
        END

        -- Get department name
        -- MIGRATION NOTE: Oracle NO_DATA_FOUND exception converted to @@ROWCOUNT check
        -- Assumes department_id is unique (PK) so TOO_MANY_ROWS cannot occur
        SELECT @v_dept_name = department_name
        FROM [dbo].[departments]
        WHERE department_id = @p_department_id;

        IF @@ROWCOUNT = 0
        BEGIN
            SET @v_error_msg = CONCAT(N'Department not found: ', @p_department_id);
            THROW 50003, @v_error_msg, 1;
        END

        PRINT CONCAT(N'Processing bonuses for department: ', @v_dept_name);

        BEGIN TRANSACTION;

        -- Cursor loop
        -- MIGRATION NOTE: Oracle cursor FOR LOOP converted to DECLARE CURSOR + FETCH + WHILE
        OPEN c_employees;
        FETCH NEXT FROM c_employees INTO @v_employee_id, @v_first_name, @v_last_name, @v_cur_salary, @v_commission_pct;

        WHILE @@FETCH_STATUS = 0
        BEGIN
            SET @v_bonus = @v_cur_salary * (@p_bonus_pct / 100);

            -- Apply commission adjustment
            IF @v_commission_pct IS NOT NULL
            BEGIN
                SET @v_bonus = @v_bonus * (1 + @v_commission_pct);
            END

            -- Cap the bonus
            IF @v_bonus > @v_max_bonus
            BEGIN
                SET @v_bonus = @v_max_bonus;
                PRINT CONCAT(N'Bonus capped for: ', @v_first_name, N' ', @v_last_name);
            END

            -- Update the employee record
            UPDATE [dbo].[employees]
            SET salary = salary + @v_bonus,
                updated_at = SYSDATETIMEOFFSET()        -- MIGRATION NOTE: Oracle SYSTIMESTAMP → SYSDATETIMEOFFSET()
            WHERE employee_id = @v_employee_id;

            -- Log the bonus
            INSERT INTO [dbo].[bonus_log] (employee_id, bonus_amount, bonus_date, department_id)
            VALUES (@v_employee_id, @v_bonus, GETDATE(), @p_department_id);
            -- MIGRATION NOTE: Oracle SYSDATE → GETDATE(); verify bonus_log.bonus_date column type compatibility

            SET @v_processed = @v_processed + 1;
            SET @v_total = @v_total + @v_bonus;

            PRINT CONCAT(N'Processed: ', @v_last_name, N', Bonus: ', FORMAT(@v_bonus, N'#,##0.00'));

            FETCH NEXT FROM c_employees INTO @v_employee_id, @v_first_name, @v_last_name, @v_cur_salary, @v_commission_pct;
        END

        CLOSE c_employees;
        DEALLOCATE c_employees;

        SET @p_total_paid = @v_total;
        SET @p_emp_count = @v_processed;

        COMMIT TRANSACTION;

        PRINT CONCAT(N'Total bonuses paid: ', FORMAT(@v_total, N'#,##0.00'));
        PRINT CONCAT(N'Employees processed: ', @v_processed);
    END TRY
    BEGIN CATCH
        -- Clean up cursor if still open
        IF CURSOR_STATUS('local', 'c_employees') >= 0
        BEGIN
            CLOSE c_employees;
            DEALLOCATE c_employees;
        END

        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        -- MIGRATION NOTE: Oracle PRAGMA EXCEPTION_INIT(e_invalid_bonus, -20001) mapped to error 50001
        IF ERROR_NUMBER() = 50001
        BEGIN
            PRINT CONCAT(N'Error: ', ERROR_MESSAGE());
            THROW;
        END
        -- MIGRATION NOTE: Oracle DUP_VAL_ON_INDEX → SQL Server error 2627 (unique constraint) / 2601 (unique index)
        -- MIGRATION NOTE: This catches any unique violation, not only from bonus_log; review if more specific handling is needed
        ELSE IF ERROR_NUMBER() IN (2627, 2601)
        BEGIN
            THROW 50004, N'Duplicate bonus entry detected', 1;
        END
        ELSE
        BEGIN
            PRINT CONCAT(N'Unexpected error: ', ERROR_NUMBER(), N' - ', ERROR_MESSAGE());
            THROW;
        END
    END CATCH
END;
GO
