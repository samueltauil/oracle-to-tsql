-- Test file: Hierarchical query (CONNECT BY), old-style joins, empty string = NULL
-- These are the trickiest Oracle-specific patterns to convert

-- ============================================================
-- 1. CONNECT BY hierarchical query with LEVEL and SYS_CONNECT_BY_PATH
-- ============================================================

SELECT
    employee_id,
    first_name || ' ' || last_name AS employee_name,
    manager_id,
    LEVEL AS depth,
    SYS_CONNECT_BY_PATH(last_name, ' > ') AS management_chain,
    LPAD(' ', (LEVEL - 1) * 4) || last_name AS indented_name,
    CONNECT_BY_ISLEAF AS is_leaf,
    CONNECT_BY_ROOT last_name AS top_manager
FROM employees
START WITH manager_id IS NULL
CONNECT BY PRIOR employee_id = manager_id
ORDER SIBLINGS BY last_name;

-- ============================================================
-- 2. Old-style (+) outer join syntax
-- ============================================================

-- Left outer join via (+)
SELECT e.employee_id, e.last_name, d.department_name
FROM employees e, departments d
WHERE e.department_id = d.department_id(+);

-- Right outer join via (+)
SELECT e.employee_id, e.last_name, d.department_name
FROM employees e, departments d
WHERE e.department_id(+) = d.department_id;

-- Multiple (+) conditions
SELECT e.employee_id, e.last_name, d.department_name, l.city
FROM employees e, departments d, locations l
WHERE e.department_id = d.department_id(+)
  AND d.location_id = l.location_id(+)
  AND l.country_id(+) = 'US';

-- ============================================================
-- 3. Empty string = NULL (Oracle's most dangerous semantic difference)
-- ============================================================

-- In Oracle, '' IS NULL evaluates to TRUE
-- These queries behave DIFFERENTLY in SQL Server

-- This finds employees with no name in Oracle (NULL and '')
SELECT * FROM employees WHERE first_name IS NULL;

-- This inserts a NULL in Oracle ('' becomes NULL)
INSERT INTO employees (employee_id, first_name, last_name, hire_date, email)
VALUES (999, '', 'TestUser', SYSDATE, 'test@example.com');

-- NVL with empty string — in Oracle NVL('', 'default') returns 'default'
SELECT NVL(first_name, 'No Name') AS display_name FROM employees;

-- String comparison with empty string
SELECT * FROM employees WHERE first_name = '';      -- Never true in Oracle ('' IS NULL)
SELECT * FROM employees WHERE first_name IS NOT NULL; -- Excludes '' in Oracle

-- Concatenation with empty/null string
SELECT first_name || '' || last_name FROM employees; -- '' treated as NULL, but || ignores NULL

-- ============================================================
-- 4. DECODE with NULL comparisons
-- ============================================================

-- DECODE treats NULL = NULL as TRUE (unlike CASE WHEN)
SELECT
    employee_id,
    DECODE(manager_id, NULL, 'CEO', 'Has Manager')          AS mgr_status,
    DECODE(commission_pct, NULL, 0, commission_pct * salary) AS commission,
    DECODE(first_name, NULL, last_name, first_name || ' ' || last_name) AS full_name
FROM employees;

-- ============================================================
-- 5. ROWNUM with ORDER BY (order of evaluation trap)
-- ============================================================

-- WARNING: This does NOT return the top 5 highest-paid employees!
-- Oracle assigns ROWNUM before ORDER BY
SELECT employee_id, last_name, salary
FROM employees
WHERE ROWNUM <= 5
ORDER BY salary DESC;

-- Correct Oracle pattern (subquery)
SELECT * FROM (
    SELECT employee_id, last_name, salary
    FROM employees
    ORDER BY salary DESC
)
WHERE ROWNUM <= 5;

-- Pagination pattern
SELECT * FROM (
    SELECT a.*, ROWNUM rn FROM (
        SELECT employee_id, last_name, salary
        FROM employees
        ORDER BY salary DESC
    ) a
    WHERE ROWNUM <= 30
)
WHERE rn > 20;

-- ============================================================
-- 6. RETURNING INTO clause
-- ============================================================

DECLARE
    v_new_id  NUMBER;
BEGIN
    INSERT INTO employees (employee_id, first_name, last_name, hire_date, email, salary)
    VALUES (emp_seq.NEXTVAL, 'John', 'Doe', SYSDATE, 'john.doe@example.com', 75000)
    RETURNING employee_id INTO v_new_id;

    DBMS_OUTPUT.PUT_LINE('New employee ID: ' || v_new_id);
END;
/

-- ============================================================
-- 7. EXECUTE IMMEDIATE (dynamic SQL)
-- ============================================================

CREATE OR REPLACE PROCEDURE archive_old_records (
    p_table_name  IN VARCHAR2,
    p_days_old    IN NUMBER
)
IS
    v_sql     VARCHAR2(4000);
    v_count   NUMBER;
BEGIN
    -- Dynamic SQL with bind variables
    v_sql := 'SELECT COUNT(*) FROM ' || p_table_name ||
             ' WHERE created_at < SYSDATE - :days';
    EXECUTE IMMEDIATE v_sql INTO v_count USING p_days_old;

    DBMS_OUTPUT.PUT_LINE('Records to archive: ' || v_count);

    -- Dynamic DML
    v_sql := 'INSERT INTO ' || p_table_name || '_archive ' ||
             'SELECT * FROM ' || p_table_name ||
             ' WHERE created_at < SYSDATE - :days';
    EXECUTE IMMEDIATE v_sql USING p_days_old;

    v_sql := 'DELETE FROM ' || p_table_name ||
             ' WHERE created_at < SYSDATE - :days';
    EXECUTE IMMEDIATE v_sql USING p_days_old;

    COMMIT;
END archive_old_records;
/

-- ============================================================
-- 8. BULK COLLECT and FORALL
-- ============================================================

DECLARE
    TYPE t_emp_ids IS TABLE OF employees.employee_id%TYPE;
    TYPE t_salaries IS TABLE OF employees.salary%TYPE;
    l_emp_ids   t_emp_ids;
    l_salaries  t_salaries;
BEGIN
    SELECT employee_id, salary
    BULK COLLECT INTO l_emp_ids, l_salaries
    FROM employees
    WHERE department_id = 10;

    FORALL i IN 1..l_emp_ids.COUNT
        UPDATE employees
        SET salary = l_salaries(i) * 1.1
        WHERE employee_id = l_emp_ids(i);

    DBMS_OUTPUT.PUT_LINE('Updated ' || SQL%ROWCOUNT || ' employees');
    COMMIT;
END;
/
