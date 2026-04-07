/*
 * Converted from: oracle-sql/02_function_conversions.sql
 * Description:     Oracle function conversions - NVL, NVL2, DECODE, string ops,
 *                  date ops, ROWNUM, DUAL, LISTAGG, GREATEST/LEAST, etc.
 *
 * MIGRATION NOTE: Oracle treats empty string ('') as NULL. SQL Server does not.
 *   Review all NULL/empty-string checks if migrated data may contain empty strings.
 */
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- NVL and COALESCE patterns
SELECT
    employee_id,
    COALESCE(first_name, N'Unknown')                                        AS first_name,
    IIF(commission_pct IS NOT NULL, salary * commission_pct, 0)             AS commission_amount,
    COALESCE(notes, email, N'N/A')                                          AS contact_info
FROM [dbo].[employees];
GO

-- DECODE with NULL comparison (tricky!)
-- MIGRATION NOTE: Oracle DECODE treats NULL=NULL as true; CASE does not.
-- Where NULL comparison values exist, CASE WHEN ... IS NULL is used instead of simple CASE.
SELECT
    employee_id,
    CASE department_id
        WHEN 10 THEN N'Finance'
        WHEN 20 THEN N'IT'
        WHEN 30 THEN N'Sales'
        ELSE N'Other'
    END                                                                     AS dept_name,
    CASE
        WHEN commission_pct IS NULL THEN N'No Commission'
        ELSE N'Has Commission'
    END                                                                     AS commission_status,
    -- MIGRATION NOTE: Oracle DECODE returns NULL (implicit default) for unmatched, non-NULL values.
    -- No ELSE clause here: values other than 1, 0, or NULL will return NULL, matching Oracle behavior.
    CASE
        WHEN is_active = 1 THEN N'Active'
        WHEN is_active = 0 THEN N'Inactive'
        WHEN is_active IS NULL THEN N'Unknown'
    END                                                                     AS status
FROM [dbo].[employees];
GO

-- String concatenation with CONCAT (handles NULLs gracefully)
-- MIGRATION NOTE: Oracle || returns NULL if any operand is NULL; CONCAT treats NULL as empty string.
-- MIGRATION NOTE: Oracle treats '' as NULL, so NVL(first_name, '') is a no-op in Oracle.
-- In T-SQL, COALESCE(first_name, N'') returns empty string. CONCAT already handles NULLs, so the net effect is equivalent.
SELECT
    employee_id,
    CONCAT(first_name, N' ', last_name)                                     AS full_name,
    CONCAT(last_name, N', ', first_name)                                    AS formal_name,
    CONCAT(N'Employee: ', employee_id, N' - ', COALESCE(first_name, N''), N' ', last_name) AS display
FROM [dbo].[employees];
GO

-- String functions
-- MIGRATION NOTE: LEN() trims trailing spaces; Oracle LENGTH() does not. Use DATALENGTH() if trailing spaces matter.
-- MIGRATION NOTE: TRANSLATE requires SQL Server 2017+.
SELECT
    employee_id,
    SUBSTRING(last_name, 1, 3)                                              AS name_prefix,
    SUBSTRING(email, CHARINDEX(N'@', email) + 1, LEN(email))               AS email_domain,
    LEN(notes)                                                              AS notes_length,
    RIGHT(REPLICATE(N'0', 10) + LEFT(CAST(employee_id AS NVARCHAR(10)), 10), 10) AS padded_id,
    LEFT(last_name + REPLICATE(N'.', 30), 30)                              AS padded_name,
    TRIM(first_name)                                                        AS trimmed_name,
    REPLACE(phone_number, N'-', N'')                                        AS clean_phone,
    TRANSLATE(phone_number, N'()-. ', N'     ')                             AS translated_phone
FROM [dbo].[employees];
GO

-- Date functions
-- MIGRATION NOTE: Oracle date arithmetic (date + number) adds days; T-SQL requires DATEADD.
-- MIGRATION NOTE: MONTHS_BETWEEN returns fractional months in Oracle; DATEDIFF(MONTH) returns integer boundary crossings only.
-- MIGRATION NOTE: NEXT_DAY assumes @@DATEFIRST = 7 (US default, Sunday=1). Adjust if server setting differs.
SELECT
    employee_id,
    GETDATE()                                                               AS current_date_time,
    SYSDATETIMEOFFSET()                                                     AS current_timestamp,
    CAST(GETDATE() AS DATE)                                                 AS today,
    -- MIGRATION NOTE: TRUNC(date, 'MM') equivalent. SQL Server 2022+ can use DATETRUNC(MONTH, hire_date).
    DATEADD(MONTH, DATEDIFF(MONTH, 0, hire_date), 0)                       AS hire_month,
    DATEADD(MONTH, 6, hire_date)                                            AS review_date,
    DATEDIFF(MONTH, hire_date, GETDATE())                                   AS months_employed,
    EOMONTH(hire_date)                                                      AS month_end,
    -- MIGRATION NOTE: Oracle NEXT_DAY(d, 'MONDAY') returns the next Monday strictly after d.
    -- Formula assumes @@DATEFIRST = 7 (Sunday=1, Monday=2). If @@DATEFIRST differs, results will be wrong.
    -- MIGRATION TODO: Verify @@DATEFIRST setting on target server, or SET DATEFIRST 7 in session.
    DATEADD(DAY, ((8 - DATEPART(WEEKDAY, GETDATE())) % 7) + 1, GETDATE()) AS next_monday,
    DATEADD(DAY, 90, hire_date)                                             AS probation_end,
    FORMAT(hire_date, 'yyyy-MM-dd')                                         AS hire_date_str,
    -- MIGRATION NOTE: FORMAT is culture-sensitive. Oracle TO_CHAR(salary, '999,999.99') may differ in padding/sign handling.
    FORMAT(salary, N'#,##0.00')                                             AS salary_formatted,
    TRY_CONVERT(DATETIME2(0), N'2024-01-15', 23)                           AS fixed_date,
    TRY_CAST(N'12345.67' AS DECIMAL(18,2))                                 AS parsed_number
FROM [dbo].[employees];
GO

-- ROWNUM pagination
-- MIGRATION NOTE: Oracle ROWNUM is assigned before ORDER BY with no guaranteed row order.
-- Using ROW_NUMBER() with ORDER BY (SELECT 1) to preserve the arbitrary-order semantics.
-- MIGRATION WARNING: Arbitrary ordering is non-deterministic. Add a meaningful ORDER BY if stable pagination is required.
SELECT employee_id, last_name, salary
FROM (
    SELECT employee_id, last_name, salary,
           ROW_NUMBER() OVER (ORDER BY (SELECT 1)) AS rn
    FROM [dbo].[employees]
) sub
WHERE rn BETWEEN 11 AND 20;
GO

-- DUAL table usage (not needed in T-SQL)
SELECT GETDATE();
GO
SELECT N'Hello World' AS greeting;
GO
SELECT NEXT VALUE FOR [dbo].[emp_seq];
GO

-- Aggregate with STRING_AGG
-- MIGRATION NOTE: STRING_AGG requires SQL Server 2017+. WITHIN GROUP (ORDER BY) requires SQL Server 2022+.
-- For SQL Server 2017-2019, remove WITHIN GROUP and apply ordering via subquery if needed.
SELECT
    department_id,
    STRING_AGG(last_name, N', ') WITHIN GROUP (ORDER BY last_name)          AS team_members,
    COUNT(*)                                                                AS member_count
FROM [dbo].[employees]
GROUP BY department_id;
GO

-- GREATEST / LEAST
-- MIGRATION NOTE: Oracle GREATEST/LEAST return NULL if any argument is NULL.
-- SQL Server MAX/MIN in VALUES ignores NULLs. A CASE guard preserves Oracle NULL semantics.
-- SQL Server 2022+ supports GREATEST() and LEAST() natively (also returns NULL if any arg is NULL).
SELECT
    employee_id,
    CASE
        WHEN salary IS NULL THEN NULL
        ELSE (SELECT MAX(v) FROM (VALUES (salary),(50000),(COALESCE(salary * commission_pct, 0))) AS T(v))
    END                                                                     AS effective_pay,
    CASE
        WHEN hire_date IS NULL THEN NULL
        ELSE (SELECT MIN(v) FROM (VALUES (hire_date),(DATEADD(DAY, -365, GETDATE()))) AS T(v))
    END                                                                     AS earlier_date
FROM [dbo].[employees];
GO

-- MOD and TRUNC on numbers
-- MIGRATION NOTE: ROUND with third argument 1 performs truncation (equivalent to Oracle TRUNC).
-- Using 12.0 to ensure decimal division (Oracle NUMBER always does decimal division).
SELECT
    employee_id,
    employee_id % 2                                                         AS is_odd,
    ROUND(salary / 12.0, 2, 1)                                             AS monthly_salary,
    ROUND(salary / 12.0, 2)                                                 AS monthly_salary_rounded
FROM [dbo].[employees];
GO

-- EXCEPT (Oracle MINUS equivalent)
SELECT department_id FROM [dbo].[employees]
EXCEPT
SELECT department_id FROM [dbo].[departments] WHERE location_id = 1700;
GO
