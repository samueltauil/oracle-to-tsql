-- =============================================
-- Converted from: oracle-sql/01_datatypes_table.sql
-- Test file: Oracle data types → T-SQL data type mapping
-- Covers all major Oracle types that require conversion
-- =============================================

SET ANSI_NULLS ON;
GO

SET QUOTED_IDENTIFIER ON;
GO

CREATE TABLE [dbo].[employees] (
    [employee_id]       BIGINT              NOT NULL,           -- MIGRATION NOTE: Oracle NUMBER(10) → BIGINT (p>9, p≤18)
    [first_name]        NVARCHAR(50),
    [last_name]         NVARCHAR(100)       NOT NULL,
    [email]             NVARCHAR(200),
    [phone_number]      NVARCHAR(20),
    [hire_date]         DATETIME2(0)        NOT NULL,           -- MIGRATION NOTE: Oracle DATE includes time; use DATETIME2(0)
    [salary]            DECIMAL(10,2),
    [commission_pct]    DECIMAL(4,2),
    [department_id]     INT,                                    -- MIGRATION NOTE: Oracle NUMBER(5) → INT (p≤9)
    [is_active]         BIT                 DEFAULT 1,          -- MIGRATION NOTE: Oracle NUMBER(1) used as boolean → BIT
    [notes]             NVARCHAR(MAX),                          -- MIGRATION NOTE: Oracle CLOB → NVARCHAR(MAX)
    [photo]             VARBINARY(MAX),                         -- MIGRATION NOTE: Oracle BLOB → VARBINARY(MAX)
    [resume]            NVARCHAR(MAX),                          -- MIGRATION NOTE: Oracle NCLOB → NVARCHAR(MAX)
    [badge_raw]         VARBINARY(16),                          -- MIGRATION NOTE: Oracle RAW(16) → VARBINARY(16)
    [created_at]        DATETIME2           DEFAULT SYSDATETIME(), -- MIGRATION NOTE: Oracle TIMESTAMP DEFAULT SYSTIMESTAMP; using SYSDATETIME() to match DATETIME2 column type
    [updated_at]        DATETIMEOFFSET,                         -- MIGRATION NOTE: Oracle TIMESTAMP WITH TIME ZONE → DATETIMEOFFSET
    [yearly_bonus]      REAL,                                   -- MIGRATION NOTE: Oracle BINARY_FLOAT → REAL
    [lifetime_value]    FLOAT,                                  -- MIGRATION NOTE: Oracle BINARY_DOUBLE → FLOAT
    [metadata]          XML,                                    -- MIGRATION NOTE: Oracle XMLTYPE → XML
    [legacy_desc]       NVARCHAR(MAX),                          -- MIGRATION NOTE: Oracle LONG → NVARCHAR(MAX); LONG is deprecated in Oracle
    CONSTRAINT [pk_employees] PRIMARY KEY ([employee_id]),
    CONSTRAINT [uq_employees_email] UNIQUE ([email]),
    CONSTRAINT [chk_salary] CHECK ([salary] > 0),
    CONSTRAINT [fk_dept] FOREIGN KEY ([department_id])
        REFERENCES [dbo].[departments]([department_id])
);
GO

CREATE SEQUENCE [dbo].[emp_seq]
    AS BIGINT
    START WITH 1000
    INCREMENT BY 1
    NO CACHE
    NO CYCLE;
GO

CREATE INDEX [idx_emp_dept] ON [dbo].[employees]([department_id]);
GO

CREATE INDEX [idx_emp_hire] ON [dbo].[employees]([hire_date]);
GO

CREATE INDEX [idx_emp_name] ON [dbo].[employees]([last_name], [first_name]);
GO
