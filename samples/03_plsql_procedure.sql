-- Test file: PL/SQL procedure with cursors, exception handling, variables
-- Covers %TYPE, %ROWTYPE, FOR LOOP cursors, RAISE_APPLICATION_ERROR

CREATE OR REPLACE PROCEDURE process_department_bonuses (
    p_department_id  IN  NUMBER,
    p_bonus_pct      IN  NUMBER,
    p_total_paid     OUT NUMBER,
    p_emp_count      OUT NUMBER
)
IS
    v_emp_name    employees.last_name%TYPE;
    v_salary      employees.salary%TYPE;
    v_bonus       NUMBER(10,2);
    v_max_bonus   CONSTANT NUMBER := 50000;
    v_dept_name   VARCHAR2(100);
    v_processed   NUMBER := 0;
    v_total       NUMBER := 0;

    -- Explicit cursor
    CURSOR c_employees IS
        SELECT employee_id, first_name, last_name, salary, commission_pct
        FROM employees
        WHERE department_id = p_department_id
          AND is_active = 1
        ORDER BY salary DESC;

    e_invalid_bonus EXCEPTION;
    PRAGMA EXCEPTION_INIT(e_invalid_bonus, -20001);

BEGIN
    -- Validate inputs
    IF p_department_id IS NULL THEN
        RAISE_APPLICATION_ERROR(-20001, 'Department ID cannot be null');
    END IF;

    IF p_bonus_pct <= 0 OR p_bonus_pct > 100 THEN
        RAISE_APPLICATION_ERROR(-20002, 'Bonus percentage must be between 0 and 100');
    END IF;

    -- Get department name (SELECT INTO with NO_DATA_FOUND)
    BEGIN
        SELECT department_name INTO v_dept_name
        FROM departments
        WHERE department_id = p_department_id;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20003, 'Department not found: ' || p_department_id);
    END;

    DBMS_OUTPUT.PUT_LINE('Processing bonuses for department: ' || v_dept_name);

    -- Cursor FOR LOOP
    FOR rec IN c_employees LOOP
        v_bonus := rec.salary * (p_bonus_pct / 100);

        -- Apply commission adjustment
        IF rec.commission_pct IS NOT NULL THEN
            v_bonus := v_bonus * (1 + rec.commission_pct);
        END IF;

        -- Cap the bonus
        IF v_bonus > v_max_bonus THEN
            v_bonus := v_max_bonus;
            DBMS_OUTPUT.PUT_LINE('Bonus capped for: ' || rec.first_name || ' ' || rec.last_name);
        END IF;

        -- Update the employee record
        UPDATE employees
        SET salary = salary + v_bonus,
            updated_at = SYSTIMESTAMP
        WHERE employee_id = rec.employee_id;

        -- Log the bonus
        INSERT INTO bonus_log (employee_id, bonus_amount, bonus_date, department_id)
        VALUES (rec.employee_id, v_bonus, SYSDATE, p_department_id);

        v_processed := v_processed + 1;
        v_total := v_total + v_bonus;

        DBMS_OUTPUT.PUT_LINE('Processed: ' || rec.last_name || ', Bonus: ' || TO_CHAR(v_bonus, '999,999.99'));
    END LOOP;

    p_total_paid := v_total;
    p_emp_count := v_processed;

    COMMIT;

    DBMS_OUTPUT.PUT_LINE('Total bonuses paid: ' || TO_CHAR(v_total, '999,999.99'));
    DBMS_OUTPUT.PUT_LINE('Employees processed: ' || v_processed);

EXCEPTION
    WHEN e_invalid_bonus THEN
        ROLLBACK;
        DBMS_OUTPUT.PUT_LINE('Error: ' || SQLERRM);
        RAISE;
    WHEN DUP_VAL_ON_INDEX THEN
        ROLLBACK;
        RAISE_APPLICATION_ERROR(-20004, 'Duplicate bonus entry detected');
    WHEN OTHERS THEN
        ROLLBACK;
        DBMS_OUTPUT.PUT_LINE('Unexpected error: ' || SQLCODE || ' - ' || SQLERRM);
        RAISE;
END process_department_bonuses;
/
