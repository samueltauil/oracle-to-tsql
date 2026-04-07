-- Test file: Oracle package (spec + body) → T-SQL schema + procedures
-- This is the most complex conversion pattern

-- ============================================================
-- Package Specification
-- ============================================================

CREATE OR REPLACE PACKAGE pkg_employee_mgmt AS

    -- Constants
    gc_max_salary     CONSTANT NUMBER := 500000;
    gc_min_salary     CONSTANT NUMBER := 30000;
    gc_default_dept   CONSTANT NUMBER := 10;

    -- Types
    TYPE t_employee_rec IS RECORD (
        emp_id     employees.employee_id%TYPE,
        full_name  VARCHAR2(200),
        salary     employees.salary%TYPE,
        dept_name  VARCHAR2(100)
    );
    TYPE t_employee_tab IS TABLE OF t_employee_rec INDEX BY PLS_INTEGER;

    -- REF CURSOR type
    TYPE t_emp_cursor IS REF CURSOR;

    -- Public procedures
    PROCEDURE hire_employee (
        p_first_name   IN  VARCHAR2,
        p_last_name    IN  VARCHAR2,
        p_email        IN  VARCHAR2,
        p_salary       IN  NUMBER    DEFAULT gc_min_salary,
        p_dept_id      IN  NUMBER    DEFAULT gc_default_dept,
        p_employee_id  OUT NUMBER
    );

    PROCEDURE terminate_employee (
        p_employee_id  IN  NUMBER,
        p_reason       IN  VARCHAR2
    );

    PROCEDURE transfer_employee (
        p_employee_id     IN  NUMBER,
        p_new_dept_id     IN  NUMBER,
        p_salary_adjust   IN  NUMBER DEFAULT 0
    );

    -- Public functions
    FUNCTION get_employee_count (
        p_department_id  IN  NUMBER DEFAULT NULL
    ) RETURN NUMBER;

    FUNCTION get_department_employees (
        p_department_id  IN  NUMBER
    ) RETURN t_emp_cursor;

    FUNCTION calculate_annual_cost (
        p_department_id  IN  NUMBER
    ) RETURN NUMBER;

END pkg_employee_mgmt;
/

-- ============================================================
-- Package Body
-- ============================================================

CREATE OR REPLACE PACKAGE BODY pkg_employee_mgmt AS

    -- Private package variable (session state!)
    g_last_hire_id   NUMBER;
    g_operation_log  VARCHAR2(4000);

    -- Private helper procedure
    PROCEDURE log_operation (p_message IN VARCHAR2) IS
    BEGIN
        g_operation_log := g_operation_log || CHR(10) || TO_CHAR(SYSDATE, 'YYYY-MM-DD HH24:MI:SS') || ' - ' || p_message;
        DBMS_OUTPUT.PUT_LINE(p_message);
    END log_operation;

    -- Private validation function
    FUNCTION validate_salary (p_salary IN NUMBER) RETURN BOOLEAN IS
    BEGIN
        RETURN (p_salary >= gc_min_salary AND p_salary <= gc_max_salary);
    END validate_salary;

    -- ============================================================
    -- hire_employee
    -- ============================================================
    PROCEDURE hire_employee (
        p_first_name   IN  VARCHAR2,
        p_last_name    IN  VARCHAR2,
        p_email        IN  VARCHAR2,
        p_salary       IN  NUMBER    DEFAULT gc_min_salary,
        p_dept_id      IN  NUMBER    DEFAULT gc_default_dept,
        p_employee_id  OUT NUMBER
    ) IS
        v_emp_id  NUMBER;
    BEGIN
        IF NOT validate_salary(p_salary) THEN
            RAISE_APPLICATION_ERROR(-20010,
                'Salary ' || p_salary || ' out of range [' || gc_min_salary || ', ' || gc_max_salary || ']');
        END IF;

        IF p_first_name IS NULL OR p_last_name IS NULL THEN
            RAISE_APPLICATION_ERROR(-20011, 'First and last name are required');
        END IF;

        -- Check for duplicate email
        DECLARE
            v_exists NUMBER;
        BEGIN
            SELECT COUNT(*) INTO v_exists
            FROM employees WHERE email = p_email;

            IF v_exists > 0 THEN
                RAISE_APPLICATION_ERROR(-20012, 'Email already exists: ' || p_email);
            END IF;
        END;

        -- Insert the employee
        INSERT INTO employees (
            employee_id, first_name, last_name, email,
            hire_date, salary, department_id, is_active, created_at
        ) VALUES (
            emp_seq.NEXTVAL, p_first_name, p_last_name, p_email,
            SYSDATE, p_salary, p_dept_id, 1, SYSTIMESTAMP
        ) RETURNING employee_id INTO v_emp_id;

        p_employee_id := v_emp_id;
        g_last_hire_id := v_emp_id;

        log_operation('Hired: ' || p_first_name || ' ' || p_last_name || ' (ID: ' || v_emp_id || ')');

        COMMIT;

    EXCEPTION
        WHEN DUP_VAL_ON_INDEX THEN
            ROLLBACK;
            RAISE_APPLICATION_ERROR(-20012, 'Duplicate constraint violation during hire');
        WHEN OTHERS THEN
            ROLLBACK;
            log_operation('Error in hire_employee: ' || SQLERRM);
            RAISE;
    END hire_employee;

    -- ============================================================
    -- terminate_employee
    -- ============================================================
    PROCEDURE terminate_employee (
        p_employee_id  IN  NUMBER,
        p_reason       IN  VARCHAR2
    ) IS
        v_emp_name VARCHAR2(200);
    BEGIN
        -- Get employee info
        SELECT first_name || ' ' || last_name INTO v_emp_name
        FROM employees
        WHERE employee_id = p_employee_id;

        -- Soft delete
        UPDATE employees
        SET is_active = 0,
            updated_at = SYSTIMESTAMP
        WHERE employee_id = p_employee_id;

        -- Archive record
        INSERT INTO employee_archive (employee_id, terminated_date, reason)
        VALUES (p_employee_id, SYSDATE, p_reason);

        log_operation('Terminated: ' || v_emp_name || ' - Reason: ' || p_reason);

        COMMIT;

    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20020, 'Employee not found: ' || p_employee_id);
        WHEN OTHERS THEN
            ROLLBACK;
            log_operation('Error in terminate_employee: ' || SQLERRM);
            RAISE;
    END terminate_employee;

    -- ============================================================
    -- transfer_employee
    -- ============================================================
    PROCEDURE transfer_employee (
        p_employee_id     IN  NUMBER,
        p_new_dept_id     IN  NUMBER,
        p_salary_adjust   IN  NUMBER DEFAULT 0
    ) IS
        v_old_dept  NUMBER;
        v_new_salary NUMBER;
    BEGIN
        SELECT department_id, salary + p_salary_adjust
        INTO v_old_dept, v_new_salary
        FROM employees
        WHERE employee_id = p_employee_id;

        IF NOT validate_salary(v_new_salary) THEN
            RAISE_APPLICATION_ERROR(-20030, 'Adjusted salary out of valid range');
        END IF;

        UPDATE employees
        SET department_id = p_new_dept_id,
            salary = v_new_salary,
            updated_at = SYSTIMESTAMP
        WHERE employee_id = p_employee_id;

        INSERT INTO transfer_log (employee_id, from_dept, to_dept, transfer_date, salary_change)
        VALUES (p_employee_id, v_old_dept, p_new_dept_id, SYSDATE, p_salary_adjust);

        log_operation('Transferred emp ' || p_employee_id ||
                      ' from dept ' || v_old_dept || ' to dept ' || p_new_dept_id);

        COMMIT;

    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20031, 'Employee not found: ' || p_employee_id);
        WHEN OTHERS THEN
            ROLLBACK;
            RAISE;
    END transfer_employee;

    -- ============================================================
    -- get_employee_count
    -- ============================================================
    FUNCTION get_employee_count (
        p_department_id  IN  NUMBER DEFAULT NULL
    ) RETURN NUMBER IS
        v_count NUMBER;
    BEGIN
        IF p_department_id IS NULL THEN
            SELECT COUNT(*) INTO v_count FROM employees WHERE is_active = 1;
        ELSE
            SELECT COUNT(*) INTO v_count
            FROM employees
            WHERE department_id = p_department_id AND is_active = 1;
        END IF;

        RETURN v_count;
    END get_employee_count;

    -- ============================================================
    -- get_department_employees (returns REF CURSOR)
    -- ============================================================
    FUNCTION get_department_employees (
        p_department_id  IN  NUMBER
    ) RETURN t_emp_cursor IS
        v_cursor t_emp_cursor;
    BEGIN
        OPEN v_cursor FOR
            SELECT e.employee_id,
                   e.first_name || ' ' || e.last_name AS full_name,
                   e.salary,
                   d.department_name
            FROM employees e
            JOIN departments d ON e.department_id = d.department_id
            WHERE e.department_id = p_department_id
              AND e.is_active = 1
            ORDER BY e.last_name;

        RETURN v_cursor;
    END get_department_employees;

    -- ============================================================
    -- calculate_annual_cost
    -- ============================================================
    FUNCTION calculate_annual_cost (
        p_department_id  IN  NUMBER
    ) RETURN NUMBER IS
        v_total NUMBER := 0;
    BEGIN
        SELECT NVL(SUM(salary * 12 + NVL(salary * commission_pct * 12, 0)), 0)
        INTO v_total
        FROM employees
        WHERE department_id = p_department_id
          AND is_active = 1;

        RETURN v_total;
    END calculate_annual_cost;

-- Package initialization block (runs once per session)
BEGIN
    g_last_hire_id := NULL;
    g_operation_log := 'Package initialized at ' || TO_CHAR(SYSDATE, 'YYYY-MM-DD HH24:MI:SS');
    DBMS_OUTPUT.PUT_LINE(g_operation_log);
END pkg_employee_mgmt;
/
