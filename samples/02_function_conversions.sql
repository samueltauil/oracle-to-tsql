-- Test file: Oracle function conversions
-- NVL, NVL2, DECODE, string ops, date ops, ROWNUM, DUAL, etc.

-- NVL and COALESCE patterns
SELECT
    employee_id,
    NVL(first_name, 'Unknown')              AS first_name,
    NVL2(commission_pct, salary * commission_pct, 0) AS commission_amount,
    NVL(notes, NVL(email, 'N/A'))           AS contact_info
FROM employees;

-- DECODE with NULL comparison (tricky!)
SELECT
    employee_id,
    DECODE(department_id, 10, 'Finance', 20, 'IT', 30, 'Sales', 'Other') AS dept_name,
    DECODE(commission_pct, NULL, 'No Commission', 'Has Commission')       AS commission_status,
    DECODE(is_active, 1, 'Active', 0, 'Inactive', NULL, 'Unknown')       AS status
FROM employees;

-- String concatenation with || and NULL handling
SELECT
    employee_id,
    first_name || ' ' || last_name          AS full_name,
    last_name || ', ' || first_name         AS formal_name,
    'Employee: ' || employee_id || ' - ' || NVL(first_name, '') || ' ' || last_name AS display
FROM employees;

-- String functions
SELECT
    employee_id,
    SUBSTR(last_name, 1, 3)                 AS name_prefix,
    SUBSTR(email, INSTR(email, '@') + 1)    AS email_domain,
    LENGTH(notes)                            AS notes_length,
    LPAD(employee_id, 10, '0')              AS padded_id,
    RPAD(last_name, 30, '.')                AS padded_name,
    TRIM(BOTH ' ' FROM first_name)          AS trimmed_name,
    REPLACE(phone_number, '-', '')          AS clean_phone,
    TRANSLATE(phone_number, '()-. ', '     ') AS translated_phone
FROM employees;

-- Date functions
SELECT
    employee_id,
    SYSDATE                                 AS current_date_time,
    SYSTIMESTAMP                             AS current_timestamp,
    TRUNC(SYSDATE)                          AS today,
    TRUNC(hire_date, 'MM')                  AS hire_month,
    ADD_MONTHS(hire_date, 6)                AS review_date,
    MONTHS_BETWEEN(SYSDATE, hire_date)      AS months_employed,
    LAST_DAY(hire_date)                     AS month_end,
    NEXT_DAY(SYSDATE, 'MONDAY')            AS next_monday,
    hire_date + 90                          AS probation_end,
    TO_CHAR(hire_date, 'YYYY-MM-DD')        AS hire_date_str,
    TO_CHAR(salary, '999,999.99')           AS salary_formatted,
    TO_DATE('2024-01-15', 'YYYY-MM-DD')    AS fixed_date,
    TO_NUMBER('12345.67')                   AS parsed_number
FROM employees;

-- ROWNUM (before ORDER BY — classic Oracle trap)
SELECT * FROM (
    SELECT employee_id, last_name, salary, ROWNUM AS rn
    FROM employees
    WHERE ROWNUM <= 20
)
WHERE rn > 10;

-- DUAL table usage
SELECT SYSDATE FROM DUAL;
SELECT 'Hello World' AS greeting FROM DUAL;
SELECT emp_seq.NEXTVAL FROM DUAL;

-- Aggregate with LISTAGG
SELECT
    department_id,
    LISTAGG(last_name, ', ') WITHIN GROUP (ORDER BY last_name) AS team_members,
    COUNT(*) AS member_count
FROM employees
GROUP BY department_id;

-- GREATEST / LEAST
SELECT
    employee_id,
    GREATEST(salary, 50000, NVL(salary * commission_pct, 0)) AS effective_pay,
    LEAST(hire_date, SYSDATE - 365) AS earlier_date
FROM employees;

-- MOD and TRUNC on numbers
SELECT
    employee_id,
    MOD(employee_id, 2)                     AS is_odd,
    TRUNC(salary / 12, 2)                   AS monthly_salary,
    ROUND(salary / 12, 2)                   AS monthly_salary_rounded
FROM employees;

-- MINUS operator
SELECT department_id FROM employees
MINUS
SELECT department_id FROM departments WHERE location_id = 1700;
